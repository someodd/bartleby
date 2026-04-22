module Bartleby.PipelineSpec (spec) where

import qualified Bartleby.Pipeline as Pipeline

import qualified Data.Text.IO as TIO
import qualified Data.Text as T
import System.Directory (doesFileExist, removePathForcibly)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import Test.Hspec

fixtureRoot :: FilePath
fixtureRoot = "test/fixtures/walker/basic"

cleanup :: IO ()
cleanup = do
  removePathForcibly (fixtureRoot </> "catalog")
  removePathForcibly (fixtureRoot </> "catalog.tmp")

spec :: Spec
spec = beforeAll_ cleanup $ afterAll_ cleanup $
  describe "Bartleby.Pipeline.run" $ do

    it "exits 0 on a valid fixture library" $ do
      code <- Pipeline.run fixtureRoot
      code `shouldBe` ExitSuccess

    it "writes catalog/.gophermap at the root" $ do
      _ <- Pipeline.run fixtureRoot
      doesFileExist (fixtureRoot </> "catalog" </> ".gophermap")
        `shouldReturn` True

    it "writes catalog/feed.xml at the root" $ do
      _ <- Pipeline.run fixtureRoot
      doesFileExist (fixtureRoot </> "catalog" </> "feed.xml")
        `shouldReturn` True

    it "writes a gophermap for every sub-classification" $ do
      _ <- Pipeline.run fixtureRoot
      doesFileExist (fixtureRoot </> "catalog" </> "recipes" </> ".gophermap")
        `shouldReturn` True
      doesFileExist (fixtureRoot </> "catalog" </> "notes" </> ".gophermap")
        `shouldReturn` True

    it "root gophermap mentions each sub-classification" $ do
      _ <- Pipeline.run fixtureRoot
      content <- TIO.readFile (fixtureRoot </> "catalog" </> ".gophermap")
      -- Recipes has a bcard title; notes uses its dirname.
      content `shouldSatisfy` T.isInfixOf (T.pack "Recipes")
      content `shouldSatisfy` T.isInfixOf (T.pack "notes")

    it "root feed mentions the library title" $ do
      _ <- Pipeline.run fixtureRoot
      content <- TIO.readFile (fixtureRoot </> "catalog" </> "feed.xml")
      content `shouldSatisfy` T.isInfixOf (T.pack "<title>basic</title>")

    it "rerun is idempotent (second run succeeds after first)" $ do
      _ <- Pipeline.run fixtureRoot
      code <- Pipeline.run fixtureRoot
      code `shouldBe` ExitSuccess

    it "fails cleanly when bartleby.conf is absent" $ do
      -- Point at a directory that has no bartleby.conf (the project root)
      code <- Pipeline.run "."
      code `shouldBe` ExitFailure 1
