module Bartleby.GophermapSpec (spec) where

import qualified Bartleby.Gophermap as Gophermap
import Bartleby.ItemTypes (defaultItemTypes)
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
  , cfgTitle             = Nothing
  , cfgDescription       = Nothing
  , cfgRecentCount       = 10
  , cfgFeedCount         = 50
  , cfgTextPreviewBytes  = 4096
  , cfgGophermapFilename = ".gophermap"
  , cfgItemTypes         = defaultItemTypes
  , cfgIncludeDotfiles   = False
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

    it "collapses tabs inside descriptions to a single space" $ do
      -- Description text now flows through summarizeDescription,
      -- which collapses every whitespace run (tabs included) to a
      -- single space — the same shape used by atom <summary>.
      let w = sampleWork { workDescription = "a\tb\tc" }
          cls = (emptyClassification "x")
            { clsWorks = [w], clsTotalWorks = 1 }
          rendered = Gophermap.renderClassification defaultConfig cls
      rendered `shouldSatisfy` (not . T.isInfixOf (T.pack "a\tb"))
      rendered `shouldSatisfy` T.isInfixOf (T.pack "a b c")

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

  describe "section ordering" $ do
    -- Recent Accessions sources only from sub-classifications, so the
    -- fixture's sub needs at least one work for Recent to render at
    -- all. cfgRecentCount=1 keeps the output predictable.
    let smallRecent = defaultConfig { cfgRecentCount = 1 }
        manyWorks   = [ sampleWork { workTitle = T.pack ("Direct " <> show i)
                                   , workSourcePath = "w" <> show i <> ".jpg" }
                      | i <- [1 .. 3 :: Int] ]
        subWork     = sampleWork { workTitle = "Sub Work"
                                 , workSourcePath = "sub/sw.jpg" }
        sub         = (emptyClassification "Sub")
                        { clsSourcePath = "sub"
                        , clsWorks      = [subWork]
                        , clsTotalWorks = 1
                        }
        cls         = (emptyClassification "Top")
                        { clsSubs       = [sub]
                        , clsWorks      = manyWorks
                        , clsTotalWorks = length manyWorks + clsTotalWorks sub
                        }

    it "renders Classifications before Class-Here Works" $ do
      let rendered = Gophermap.renderClassification smallRecent cls
          subIdx   = T.breakOn (T.pack "Classifications")   rendered
          workIdx  = T.breakOn (T.pack "Class-Here Works")  rendered
      T.length (fst subIdx) < T.length (fst workIdx) `shouldBe` True

    it "renders Class-Here Works before Recent Accessions" $ do
      let rendered = Gophermap.renderClassification smallRecent cls
          workIdx   = T.breakOn (T.pack "Class-Here Works")  rendered
          recentIdx = T.breakOn (T.pack "Recent Accessions") rendered
      T.length (fst workIdx) < T.length (fst recentIdx) `shouldBe` True

    it "renders Recent Accessions before the Atom feed link" $ do
      let rendered = Gophermap.renderClassification smallRecent cls
          recentIdx = T.breakOn (T.pack "Recent Accessions") rendered
          feedIdx   = T.breakOn (T.pack "Atom feed")         rendered
      T.length (fst recentIdx) < T.length (fst feedIdx) `shouldBe` True

  describe "Recent Accessions dedup" $ do
    it "excludes direct works from Recent (they already appear in Class-Here Works)" $ do
      let direct = sampleWork
            { workTitle      = "Direct Item"
            , workSourcePath = "direct.jpg"
            , workUpdated    = fromGregorian 2026 5 10
            }
          subItem = sampleWork
            { workTitle      = "Sub Item"
            , workSourcePath = "sub/item.jpg"
            , workUpdated    = fromGregorian 2026 5 9
            }
          sub = (emptyClassification "Sub")
                  { clsSourcePath = "sub"
                  , clsWorks      = [subItem]
                  , clsTotalWorks = 1
                  }
          cls = (emptyClassification "Top")
                  { clsSubs       = [sub]
                  , clsWorks      = [direct]
                  , clsTotalWorks = 1 + clsTotalWorks sub
                  }
          rendered          = Gophermap.renderClassification defaultConfig cls
          (_, recentBlock)  = T.breakOn (T.pack "Recent Accessions") rendered
      rendered    `shouldSatisfy` T.isInfixOf (T.pack "Direct Item")  -- in Class-Here Works
      recentBlock `shouldSatisfy` T.isInfixOf (T.pack "Sub Item")
      recentBlock `shouldSatisfy` (not . T.isInfixOf (T.pack "Direct Item"))

    it "shows sub-works even when direct works are newer (filter is structural)" $ do
      let direct = sampleWork
            { workTitle      = "Newer Direct"
            , workSourcePath = "newer.jpg"
            , workUpdated    = fromGregorian 2026 5 16
            }
          subItem = sampleWork
            { workTitle      = "Older Sub"
            , workSourcePath = "sub/older.jpg"
            , workUpdated    = fromGregorian 2026 1 1
            }
          sub = (emptyClassification "Sub")
                  { clsSourcePath = "sub"
                  , clsWorks      = [subItem]
                  , clsTotalWorks = 1
                  }
          cls = (emptyClassification "Top")
                  { clsSubs       = [sub]
                  , clsWorks      = [direct]
                  , clsTotalWorks = 1 + clsTotalWorks sub
                  }
          rendered         = Gophermap.renderClassification defaultConfig cls
          (_, recentBlock) = T.breakOn (T.pack "Recent Accessions") rendered
      rendered    `shouldSatisfy` T.isInfixOf (T.pack "Recent Accessions")
      recentBlock `shouldSatisfy` T.isInfixOf (T.pack "Older Sub")
      recentBlock `shouldSatisfy` (not . T.isInfixOf (T.pack "Newer Direct"))

    it "omits Recent Accessions at a leaf classification with many works" $ do
      -- Under the old behaviour this leaf would render Recent as a
      -- prefix of Class-Here Works (20 > cfgRecentCount=10). Under
      -- the new behaviour the source set is sub-only, which is empty
      -- for a leaf, so 'null recent' fires and Recent is hidden.
      let manyWorks = [ sampleWork
                          { workTitle      = T.pack ("Item " <> show i)
                          , workSourcePath = "i" <> show i <> ".jpg"
                          }
                      | i <- [1 .. 20 :: Int]
                      ]
          cls = (emptyClassification "Leaf")
                  { clsWorks      = manyWorks
                  , clsTotalWorks = length manyWorks
                  }
          rendered = Gophermap.renderClassification defaultConfig cls
      rendered `shouldSatisfy` (not . T.isInfixOf (T.pack "Recent Accessions"))

  describe "breadcrumb" $ do
    it "omits a breadcrumb at the root (empty clsSourcePath)" $ do
      let rendered = Gophermap.renderClassification defaultConfig
                       (emptyClassification "library")
      -- The breadcrumb line, when present, starts with two spaces and
      -- contains " / " between segments. At the root there is none.
      rendered `shouldSatisfy` (not . T.isInfixOf (T.pack " / "))

    it "renders a breadcrumb line for a nested classification" $ do
      let cls = (emptyClassification "2026") { clsSourcePath = "photos/2026" }
          rendered = Gophermap.renderClassification defaultConfig cls
      rendered `shouldSatisfy` T.isInfixOf (T.pack "photos / 2026")

    it "single-segment paths still render a breadcrumb" $ do
      let cls = (emptyClassification "photos") { clsSourcePath = "photos" }
          rendered = Gophermap.renderClassification defaultConfig cls
      -- One segment, no " / " separator.
      rendered `shouldSatisfy` T.isInfixOf (T.pack "  photos")

  describe "source-dir link" $ do
    it "renders 'Browse source directory' on every classification" $ do
      let renderedRoot = Gophermap.renderClassification defaultConfig
                          (emptyClassification "library")
      renderedRoot `shouldSatisfy` T.isInfixOf (T.pack "Browse source directory")

    it "at root, selector is the library selector with a trailing slash" $ do
      let renderedRoot = Gophermap.renderClassification defaultConfig
                          (emptyClassification "library")
      -- selector = "/library", and we want a tab-separated selector
      -- of "/library/" (i.e. the raw library directory).
      renderedRoot `shouldSatisfy` T.isInfixOf (T.pack "\t/library/\t")

    it "at a nested classification, selector includes the clsSourcePath" $ do
      let cls = (emptyClassification "2026") { clsSourcePath = "photos/2026" }
          rendered = Gophermap.renderClassification defaultConfig cls
      rendered `shouldSatisfy` T.isInfixOf (T.pack "\t/library/photos/2026/\t")

    it "is a directory link (item type 1)" $ do
      let rendered = Gophermap.renderClassification defaultConfig
                       (emptyClassification "library")
      rendered `shouldSatisfy` T.isInfixOf (T.pack "1Browse source directory")
