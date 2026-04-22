module Bartleby.BCardSpec (spec) where

import qualified Bartleby.BCard as BCard
import Bartleby.Types
import qualified Data.ByteString.Char8 as BS8
import Data.Either (isLeft)
import Data.Time.Calendar (fromGregorian)
import Test.Hspec

spec :: Spec
spec = describe "Bartleby.BCard" $ do

  describe "parseBCard" $ do

    it "parses an empty bcard (all fields Nothing)" $
      case BCard.parseBCard "x.bcard" (BS8.pack "") of
        Left e -> expectationFailure e
        Right (card, warns) -> do
          cardTitle          card `shouldBe` Nothing
          cardCreated        card `shouldBe` Nothing
          cardUpdated        card `shouldBe` Nothing
          cardDescription    card `shouldBe` Nothing
          cardClassification card `shouldBe` Nothing
          warns `shouldBe` []

    it "parses a minimal title-only bcard" $
      case BCard.parseBCard "x.bcard" (BS8.pack "title: Snickerdoodles\n") of
        Left e -> expectationFailure e
        Right (card, _) ->
          cardTitle card `shouldBe` Just "Snickerdoodles"

    it "parses a full bcard" $
      let yaml = BS8.pack $ unlines
            [ "title: Snickerdoodles"
            , "created: 2026-04-20"
            , "updated: 2026-04-21"
            , "description: Grandmother's recipe"
            , "classification: false"
            ]
      in case BCard.parseBCard "x.bcard" yaml of
        Left e -> expectationFailure e
        Right (card, warns) -> do
          cardTitle          card `shouldBe` Just "Snickerdoodles"
          cardCreated        card `shouldBe` Just (fromGregorian 2026 4 20)
          cardUpdated        card `shouldBe` Just (fromGregorian 2026 4 21)
          cardDescription    card `shouldBe` Just "Grandmother's recipe"
          cardClassification card `shouldBe` Just False
          warns `shouldBe` []

    it "parses a multi-line description" $
      let yaml = BS8.pack $ unlines
            [ "title: X"
            , "description: |"
            , "  line one"
            , "  line two"
            ]
      in case BCard.parseBCard "x.bcard" yaml of
        Left e -> expectationFailure e
        Right (card, _) ->
          cardDescription card `shouldBe` Just "line one\nline two\n"

    it "atomic failure: rejects malformed date" $
      BCard.parseBCard "x.bcard" (BS8.pack "created: nopenope\n")
        `shouldSatisfy` isLeft

    it "atomic failure: rejects non-text title" $
      BCard.parseBCard "x.bcard" (BS8.pack "title: [a, b]\n")
        `shouldSatisfy` isLeft

    it "atomic failure: rejects non-boolean classification" $
      BCard.parseBCard "x.bcard" (BS8.pack "classification: maybe\n")
        `shouldSatisfy` isLeft

    it "rejects a non-mapping root" $
      BCard.parseBCard "x.bcard" (BS8.pack "- one\n- two\n")
        `shouldSatisfy` isLeft

    it "warns on unknown field but still parses" $
      let yaml = BS8.pack "title: X\ntilte: Y\nextra: 42\n"
      in case BCard.parseBCard "x.bcard" yaml of
        Left e -> expectationFailure e
        Right (card, warns) -> do
          cardTitle card `shouldBe` Just "X"
          length warns `shouldBe` 2

    it "classification: true parses" $
      case BCard.parseBCard "x.bcard" (BS8.pack "classification: true\n") of
        Left e -> expectationFailure e
        Right (card, _) ->
          cardClassification card `shouldBe` Just True

    it "accepts only partial dates (created without updated)" $
      let yaml = BS8.pack "title: X\ncreated: 2026-04-20\n"
      in case BCard.parseBCard "x.bcard" yaml of
        Left e -> expectationFailure e
        Right (card, _) -> do
          cardCreated card `shouldBe` Just (fromGregorian 2026 4 20)
          cardUpdated card `shouldBe` Nothing
