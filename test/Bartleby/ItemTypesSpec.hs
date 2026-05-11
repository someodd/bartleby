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

  describe "lookupItemType with overrides" $ do
    let m = Map.insert ".wat" Type0 defaultItemTypes
    it "honours an added extension" $
      lookupItemType m "x.wat" `shouldBe` Type0
    it "leaves defaults intact"     $
      lookupItemType m "x.txt" `shouldBe` Type0

    let m' = Map.insert ".md" TypeH defaultItemTypes
    it "honours an overriding extension" $
      lookupItemType m' "x.md" `shouldBe` TypeH

  describe "parseItemTypeChar" $ do
    it "accepts \"0\""  $ parseItemTypeChar "0" `shouldBe` Right Type0
    it "accepts \"I\""  $ parseItemTypeChar "I" `shouldBe` Right TypeI
    it "accepts \"g\""  $ parseItemTypeChar "g" `shouldBe` Right TypeG
    it "accepts \"s\""  $ parseItemTypeChar "s" `shouldBe` Right TypeS
    it "accepts \"h\""  $ parseItemTypeChar "h" `shouldBe` Right TypeH
    it "accepts \"9\""  $ parseItemTypeChar "9" `shouldBe` Right Type9

    it "rejects \"1\" with a directory-specific message" $
      case parseItemTypeChar "1" of
        Left msg -> msg `shouldContain` "directory"
        Right _  -> expectationFailure "expected '1' to be rejected"

    it "rejects an unknown single char"   $ parseItemTypeChar "x"    `shouldSatisfy` isLeft
    it "rejects an empty string"          $ parseItemTypeChar ""     `shouldSatisfy` isLeft
    it "rejects a multi-character string" $ parseItemTypeChar "text" `shouldSatisfy` isLeft
