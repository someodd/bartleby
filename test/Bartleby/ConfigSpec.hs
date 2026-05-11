module Bartleby.ConfigSpec (spec) where

import qualified Bartleby.Config as Config
import Bartleby.ItemTypes (defaultItemTypes)
import Bartleby.Types
import qualified Data.ByteString.Char8 as BS8
import Data.Either (isLeft)
import qualified Data.Map.Strict as Map
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
          cfgSelector          cfg `shouldBe` Selector ""
          cfgRecentCount       cfg `shouldBe` 10
          cfgFeedCount         cfg `shouldBe` 50
          cfgTextPreviewBytes  cfg `shouldBe` 4096
          cfgGophermapFilename cfg `shouldBe` ".gophermap"
          cfgItemTypes         cfg `shouldBe` defaultItemTypes
          cfgIncludeDotfiles   cfg `shouldBe` False
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

  describe "item_types" $ do

    it "absent ⇒ merged map equals defaultItemTypes" $ do
      let yaml = BS8.pack "hostname: a\n"
      case Config.parseConfig yaml of
        Left e -> expectationFailure e
        Right (cfg, _) -> cfgItemTypes cfg `shouldBe` defaultItemTypes

    it "adds a new extension on top of defaults" $ do
      let yaml = BS8.pack $ unlines
            [ "hostname: a"
            , "item_types:"
            , "  .wad: \"9\""
            ]
      case Config.parseConfig yaml of
        Left e -> expectationFailure e
        Right (cfg, _) -> do
          Map.lookup ".wad" (cfgItemTypes cfg) `shouldBe` Just Type9
          -- defaults still present
          Map.lookup ".txt" (cfgItemTypes cfg) `shouldBe` Just Type0

    it "user override wins over a default" $ do
      let yaml = BS8.pack $ unlines
            [ "hostname: a"
            , "item_types:"
            , "  .md: \"h\""
            ]
      case Config.parseConfig yaml of
        Left e -> expectationFailure e
        Right (cfg, _) ->
          Map.lookup ".md" (cfgItemTypes cfg) `shouldBe` Just TypeH

    it "key is lowercased before storage" $ do
      let yaml = BS8.pack $ unlines
            [ "hostname: a"
            , "item_types:"
            , "  .MD: \"h\""
            ]
      case Config.parseConfig yaml of
        Left e -> expectationFailure e
        Right (cfg, _) -> do
          Map.lookup ".md" (cfgItemTypes cfg) `shouldBe` Just TypeH
          Map.lookup ".MD" (cfgItemTypes cfg) `shouldBe` Nothing

    it "rejects a key without leading dot" $
      Config.parseConfig (BS8.pack "hostname: a\nitem_types:\n  wad: \"9\"\n")
        `shouldSatisfy` isLeft

    it "rejects a key that is just \".\"" $
      Config.parseConfig (BS8.pack "hostname: a\nitem_types:\n  \".\": \"9\"\n")
        `shouldSatisfy` isLeft

    it "rejects a key containing a slash" $
      Config.parseConfig (BS8.pack "hostname: a\nitem_types:\n  \".a/b\": \"9\"\n")
        `shouldSatisfy` isLeft

    it "accepts value \"1\" (menu — for CGI scripts that emit a gopher menu)" $ do
      let yaml = BS8.pack $ unlines
            [ "hostname: a"
            , "item_types:"
            , "  .cgi: \"1\""
            ]
      case Config.parseConfig yaml of
        Left e -> expectationFailure e
        Right (cfg, _) ->
          Map.lookup ".cgi" (cfgItemTypes cfg) `shouldBe` Just Type1

    it "rejects an unknown type char" $
      Config.parseConfig (BS8.pack "hostname: a\nitem_types:\n  .x: \"q\"\n")
        `shouldSatisfy` isLeft

    it "rejects a multi-character type value" $
      Config.parseConfig (BS8.pack "hostname: a\nitem_types:\n  .x: \"text\"\n")
        `shouldSatisfy` isLeft

    it "rejects item_types as a list" $
      Config.parseConfig (BS8.pack "hostname: a\nitem_types:\n  - .wad\n")
        `shouldSatisfy` isLeft

    it "rejects item_types as a scalar" $
      Config.parseConfig (BS8.pack "hostname: a\nitem_types: nope\n")
        `shouldSatisfy` isLeft

    it "treats a top-level typo (item_typs:) as an unknown-field warning" $ do
      let yaml = BS8.pack "hostname: a\nitem_typs: x\n"
      case Config.parseConfig yaml of
        Left e -> expectationFailure e
        Right (cfg, warns) -> do
          cfgItemTypes cfg `shouldBe` defaultItemTypes
          length warns `shouldBe` 1

  describe "include_dotfiles" $ do

    it "defaults to false when absent" $ do
      let yaml = BS8.pack "hostname: a\n"
      case Config.parseConfig yaml of
        Left e -> expectationFailure e
        Right (cfg, _) -> cfgIncludeDotfiles cfg `shouldBe` False

    it "accepts true" $ do
      let yaml = BS8.pack "hostname: a\ninclude_dotfiles: true\n"
      case Config.parseConfig yaml of
        Left e -> expectationFailure e
        Right (cfg, _) -> cfgIncludeDotfiles cfg `shouldBe` True

    it "accepts false explicitly" $ do
      let yaml = BS8.pack "hostname: a\ninclude_dotfiles: false\n"
      case Config.parseConfig yaml of
        Left e -> expectationFailure e
        Right (cfg, _) -> cfgIncludeDotfiles cfg `shouldBe` False

    it "rejects a non-bool value" $
      Config.parseConfig (BS8.pack "hostname: a\ninclude_dotfiles: maybe\n")
        `shouldSatisfy` isLeft

    it "rejects an integer" $
      Config.parseConfig (BS8.pack "hostname: a\ninclude_dotfiles: 1\n")
        `shouldSatisfy` isLeft

  describe "normalizeSelector" $ do

    it "returns \"\" (root) for an empty input" $
      Config.normalizeSelector "" `shouldBe` Selector ""

    it "returns \"\" (root) for a lone slash" $
      Config.normalizeSelector "/" `shouldBe` Selector ""

    it "returns \"\" (root) for multiple slashes" $
      Config.normalizeSelector "///" `shouldBe` Selector ""

    it "adds a leading slash if missing" $
      Config.normalizeSelector "library" `shouldBe` Selector "/library"

    it "strips a single trailing slash" $
      Config.normalizeSelector "/library/" `shouldBe` Selector "/library"

    it "strips multiple trailing slashes" $
      Config.normalizeSelector "/library///" `shouldBe` Selector "/library"

    it "handles combined missing leading + trailing slashes" $
      Config.normalizeSelector "library/" `shouldBe` Selector "/library"
