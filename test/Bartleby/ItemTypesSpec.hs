module Bartleby.ItemTypesSpec (spec) where

import Bartleby.ItemTypes
import Bartleby.Types
import Data.Either (isLeft)
import qualified Data.Map.Strict as Map
import Test.Hspec

spec :: Spec
spec = describe "Bartleby.ItemTypes" $ do

  describe "lookupItemType (defaults)" $ do
    let look = lookupItemType defaultItemTypes
    it "maps .txt to Type0"        $ look "x.txt"   `shouldBe` Type0
    it "maps .jpg to TypeI"        $ look "x.jpg"   `shouldBe` TypeI
    it "maps .gif to TypeG"        $ look "x.gif"   `shouldBe` TypeG
    it "maps .mp3 to TypeS"        $ look "x.mp3"   `shouldBe` TypeS
    it "maps .html to TypeH"       $ look "x.html"  `shouldBe` TypeH
    it "falls back to Type9"       $ look "x.wat"   `shouldBe` Type9
    it "is case-insensitive"       $ look "x.JPG"   `shouldBe` TypeI
    it "falls back on no extension" $ look "README" `shouldBe` Type9
    it "falls back on extensionless dotfile when not configured" $
      look ".plan" `shouldBe` Type9

  describe "lookupItemType with overrides" $ do
    let m = Map.insert ".wat" Type0 defaultItemTypes
    it "honours an added extension" $
      lookupItemType m "x.wat" `shouldBe` Type0
    it "leaves defaults intact"     $
      lookupItemType m "x.txt" `shouldBe` Type0

    let m' = Map.insert ".md" TypeH defaultItemTypes
    it "honours an overriding extension" $
      lookupItemType m' "x.md" `shouldBe` TypeH

  describe "lookupItemType on extensionless dotfiles" $ do
    let m = Map.fromList
              [ (".plan",      Type0)
              , (".gitignore", Type0)
              , (".signature", Type0)
              ]
    it "uses the full basename as the lookup key for .plan" $
      lookupItemType m ".plan" `shouldBe` Type0
    it "uses the full basename for .gitignore" $
      lookupItemType m ".gitignore" `shouldBe` Type0
    it "is case-insensitive on dotfile names" $
      lookupItemType m ".PLAN" `shouldBe` Type0
    it "works through a directory prefix" $
      lookupItemType m "sub/dir/.plan" `shouldBe` Type0
    it "does not affect extensionless non-dotfiles (README still Type9)" $
      lookupItemType m "README" `shouldBe` Type9
    it "extensioned-dotfiles still use the extension (.foo.txt → .txt)" $
      lookupItemType m ".foo.txt" `shouldBe` Type9
      -- ^ defaults table not included here; .txt key absent → Type9
    it "leaves regular extension lookups untouched" $
      lookupItemType (Map.insert ".plan" Type0 defaultItemTypes) "x.txt"
        `shouldBe` Type0
    it "a 1-char-name dotfile (.a) still resolves through basename" $
      lookupItemType (Map.singleton ".a" TypeH) ".a" `shouldBe` TypeH

  describe "parseItemTypeChar" $ do
    it "accepts \"0\""  $ parseItemTypeChar "0" `shouldBe` Right Type0
    it "accepts \"1\""  $ parseItemTypeChar "1" `shouldBe` Right Type1
    it "accepts \"I\""  $ parseItemTypeChar "I" `shouldBe` Right TypeI
    it "accepts \"g\""  $ parseItemTypeChar "g" `shouldBe` Right TypeG
    it "accepts \"s\""  $ parseItemTypeChar "s" `shouldBe` Right TypeS
    it "accepts \"h\""  $ parseItemTypeChar "h" `shouldBe` Right TypeH
    it "accepts \"9\""  $ parseItemTypeChar "9" `shouldBe` Right Type9

    it "rejects an unknown single char"   $ parseItemTypeChar "x"    `shouldSatisfy` isLeft
    it "rejects an empty string"          $ parseItemTypeChar ""     `shouldSatisfy` isLeft
    it "rejects a multi-character string" $ parseItemTypeChar "text" `shouldSatisfy` isLeft
