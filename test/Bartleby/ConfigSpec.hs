module Bartleby.ConfigSpec (spec) where

import qualified Bartleby.Config as Config
import Bartleby.Types
import qualified Data.ByteString.Char8 as BS8
import Data.Either (isLeft)
import Test.Hspec

spec :: Spec
spec = describe "Bartleby.Config" $ do

  describe "parseConfig" $ do

    it "parses a minimal valid config, all defaults applied" $ do
      let yaml = BS8.pack "hostname: gopher.example.com\n"
      case Config.parseConfig yaml of
        Left e -> expectationFailure e
        Right (cfg, warns) -> do
          cfgHostname          cfg `shouldBe` "gopher.example.com"
          cfgPort              cfg `shouldBe` 70
          cfgSelector          cfg `shouldBe` Selector "/"
          cfgRecentCount       cfg `shouldBe` 10
          cfgFeedCount         cfg `shouldBe` 50
          cfgTextPreviewBytes  cfg `shouldBe` 4096
          cfgGophermapFilename cfg `shouldBe` ".gophermap"
          warns `shouldBe` []

    it "rejects config without hostname" $
      Config.parseConfig (BS8.pack "port: 70\n") `shouldSatisfy` isLeft

    it "rejects port below 1" $
      Config.parseConfig (BS8.pack "hostname: a\nport: 0\n") `shouldSatisfy` isLeft

    it "rejects port above 65535" $
      Config.parseConfig (BS8.pack "hostname: a\nport: 70000\n") `shouldSatisfy` isLeft

    it "rejects a negative recent_count" $
      Config.parseConfig (BS8.pack "hostname: a\nrecent_count: -1\n")
        `shouldSatisfy` isLeft

    it "rejects a non-mapping root" $
      Config.parseConfig (BS8.pack "- one\n- two\n") `shouldSatisfy` isLeft

    it "parses a full config with all fields" $ do
      let yaml = BS8.pack $ unlines
            [ "hostname: gopher.someodd.zip"
            , "port: 7070"
            , "selector: /library"
            , "recent_count: 5"
            , "feed_count: 25"
            , "text_preview_bytes: 2048"
            ]
      case Config.parseConfig yaml of
        Left e -> expectationFailure e
        Right (cfg, warns) -> do
          cfgHostname         cfg `shouldBe` "gopher.someodd.zip"
          cfgPort             cfg `shouldBe` 7070
          cfgSelector         cfg `shouldBe` Selector "/library"
          cfgRecentCount      cfg `shouldBe` 5
          cfgFeedCount        cfg `shouldBe` 25
          cfgTextPreviewBytes cfg `shouldBe` 2048
          warns `shouldBe` []

    it "warns on unknown fields but still parses" $ do
      let yaml = BS8.pack $ unlines
            [ "hostname: a"
            , "tilte: X"        -- typo
            , "extra: 42"
            ]
      case Config.parseConfig yaml of
        Left e -> expectationFailure e
        Right (_, warns) -> length warns `shouldBe` 2

    it "accepts gophermap_filename override" $ do
      let yaml = BS8.pack "hostname: a\ngophermap_filename: gophermap\n"
      case Config.parseConfig yaml of
        Left e -> expectationFailure e
        Right (cfg, _) ->
          cfgGophermapFilename cfg `shouldBe` "gophermap"

    it "rejects an empty gophermap_filename" $
      Config.parseConfig (BS8.pack "hostname: a\ngophermap_filename: \"\"\n")
        `shouldSatisfy` isLeft

    it "rejects a gophermap_filename containing a slash" $
      Config.parseConfig (BS8.pack "hostname: a\ngophermap_filename: \"a/b\"\n")
        `shouldSatisfy` isLeft

    it "rejects gophermap_filename = '..'" $
      Config.parseConfig (BS8.pack "hostname: a\ngophermap_filename: \"..\"\n")
        `shouldSatisfy` isLeft

  describe "normalizeSelector" $ do

    it "returns \"/\" for an empty input" $
      Config.normalizeSelector "" `shouldBe` Selector "/"

    it "preserves a lone slash" $
      Config.normalizeSelector "/" `shouldBe` Selector "/"

    it "adds a leading slash if missing" $
      Config.normalizeSelector "library" `shouldBe` Selector "/library"

    it "strips a single trailing slash" $
      Config.normalizeSelector "/library/" `shouldBe` Selector "/library"

    it "strips multiple trailing slashes" $
      Config.normalizeSelector "/library///" `shouldBe` Selector "/library"

    it "handles combined missing leading + trailing slashes" $
      Config.normalizeSelector "library/" `shouldBe` Selector "/library"
