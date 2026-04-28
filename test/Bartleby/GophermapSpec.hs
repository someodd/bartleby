module Bartleby.GophermapSpec (spec) where

import qualified Bartleby.Gophermap as Gophermap
import Bartleby.Types
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Calendar (fromGregorian)
import Test.Hspec

defaultConfig :: Config
defaultConfig = Config
  { cfgHostname          = "gopher.example.com"
  , cfgPort              = 70
  , cfgSelector          = Selector "/library"
  , cfgRecentCount       = 10
  , cfgFeedCount         = 50
  , cfgTextPreviewBytes  = 4096
  , cfgGophermapFilename = ".gophermap"
  }

emptyClassification :: Text -> Classification
emptyClassification t = Classification
  { clsTitle         = t
  , clsDescription   = ""
  , clsSourcePath    = ""
  , clsSubs          = []
  , clsWorks         = []
  , clsTotalWorks    = 0
  , clsTotalSize     = 0
  , clsLatestUpdated = Nothing
  }

sampleWork :: Work
sampleWork = Work
  { workTitle       = "Cheesecake"
  , workCreated     = fromGregorian 2026 4 18
  , workUpdated     = fromGregorian 2026 4 18
  , workDescription = "Classic New York style."
  , workKind        = WorkFile TypeI
  , workSourcePath  = "recipes/cheesecake.jpg"
  , workSize        = 1200000
  , workPreview     = Nothing
  }

spec :: Spec
spec = do

  describe "formatSize" $ do
    it "under 1024 bytes shows as N B" $
      Gophermap.formatSize 453 `shouldBe` "453 B"
    it "over 1024 shows as K with one decimal" $
      Gophermap.formatSize 4500 `shouldBe` "4.4 K"
    it "shows M for megabyte scale" $
      Gophermap.formatSize 1500000 `shouldBe` "1.4 M"
    it "shows G for gigabyte scale" $
      Gophermap.formatSize (2 * 1024 * 1024 * 1024) `shouldBe` "2.0 G"

  describe "itemTypeChar" $ do
    it "text → '0'"        $ Gophermap.itemTypeChar (WorkFile Type0) `shouldBe` '0'
    it "directory → '1'"   $ Gophermap.itemTypeChar WorkDirectory    `shouldBe` '1'
    it "image → 'I'"       $ Gophermap.itemTypeChar (WorkFile TypeI) `shouldBe` 'I'
    it "gif → 'g'"         $ Gophermap.itemTypeChar (WorkFile TypeG) `shouldBe` 'g'
    it "unknown → '9'"     $ Gophermap.itemTypeChar (WorkFile Type9) `shouldBe` '9'

  describe "renderClassification" $ do

    it "renders an empty classification with the 'Holdings: none' summary" $ do
      let rendered = Gophermap.renderClassification defaultConfig
                       (emptyClassification "empty")
      rendered `shouldSatisfy` T.isInfixOf (T.pack "Holdings: none")

    it "spaces the title into the header" $ do
      let rendered = Gophermap.renderClassification defaultConfig
                       (emptyClassification "cats")
      -- "cats" → "c a t s" (intersperse ' ')
      rendered `shouldSatisfy` T.isInfixOf (T.pack "c a t s")

    it "includes the atom feed link at the bottom" $ do
      let rendered = Gophermap.renderClassification defaultConfig
                       (emptyClassification "x")
      rendered `shouldSatisfy` T.isInfixOf (T.pack "Atom feed")
      rendered `shouldSatisfy` T.isInfixOf (T.pack "/library/catalog/feed.xml")

    it "renders a work line with title, date, size, and description info-line" $ do
      let cls = (emptyClassification "recipes")
            { clsWorks      = [sampleWork]
            , clsTotalWorks = 1
            , clsTotalSize  = workSize sampleWork
            }
          rendered = Gophermap.renderClassification defaultConfig cls
      rendered `shouldSatisfy` T.isInfixOf (T.pack "Cheesecake (2026-04-18, 1.1 M)")
      rendered `shouldSatisfy` T.isInfixOf (T.pack "Classic New York style.")
      -- type-I item (image)
      rendered `shouldSatisfy` T.isInfixOf (T.pack "ICheesecake")

    it "escapes tabs inside descriptions to spaces" $ do
      let w = sampleWork { workDescription = "a\tb\tc" }
          cls = (emptyClassification "x")
            { clsWorks = [w], clsTotalWorks = 1 }
          rendered = Gophermap.renderClassification defaultConfig cls
      rendered `shouldSatisfy` (not . T.isInfixOf (T.pack "a\tb"))
      rendered `shouldSatisfy` T.isInfixOf (T.pack "a  b  c")

    it "truncates long descriptions with ellipsis" $ do
      let longDesc = T.replicate 200 "x"
          w = sampleWork { workDescription = longDesc }
          cls = (emptyClassification "x")
            { clsWorks = [w], clsTotalWorks = 1 }
          rendered = Gophermap.renderClassification defaultConfig cls
      rendered `shouldSatisfy` T.isInfixOf (T.pack (replicate 67 'x' ++ "..."))

    it "omits the description info-line when description is empty" $ do
      let w = sampleWork { workDescription = "" }
          cls = (emptyClassification "x")
            { clsWorks = [w], clsTotalWorks = 1 }
          rendered = Gophermap.renderClassification defaultConfig cls
          -- Count info lines that start with "  " in-between work/atom sections.
          -- Cheap heuristic: the word "Classic" is gone.
      rendered `shouldSatisfy` (not . T.isInfixOf (T.pack "Classic"))

    it "labels the direct-works section 'Class-Here Works'" $ do
      let cls = (emptyClassification "x")
            { clsWorks = [sampleWork], clsTotalWorks = 1 }
          rendered = Gophermap.renderClassification defaultConfig cls
      rendered `shouldSatisfy` T.isInfixOf (T.pack "Class-Here Works")

    it "omits the Class-Here Works section when there are no direct works" $ do
      let cls = emptyClassification "x"  -- no works, no subs
          rendered = Gophermap.renderClassification defaultConfig cls
      rendered `shouldSatisfy` (not . T.isInfixOf (T.pack "Class-Here Works"))
