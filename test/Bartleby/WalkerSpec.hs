module Bartleby.WalkerSpec (spec) where

import Bartleby.ItemTypes (defaultItemTypes)
import qualified Bartleby.Walker as Walker
import Bartleby.Types
import Data.List (find, sort)
import qualified Data.Text as T
import Data.Time.Calendar (fromGregorian)
import Test.Hspec

fixtureRoot :: FilePath
fixtureRoot = "test/fixtures/walker/basic"

defaultConfig :: Config
defaultConfig = Config
  { cfgHostname          = "gopher.example.com"
  , cfgPort              = 70
  , cfgSelector          = Selector "/library"
  , cfgRecentCount       = 10
  , cfgFeedCount         = 50
  , cfgTextPreviewBytes  = 4096
  , cfgGophermapFilename = ".gophermap"
  , cfgItemTypes         = defaultItemTypes
  , cfgIncludeDotfiles   = False
  }

findWork :: T.Text -> [Work] -> Maybe Work
findWork t = find (\w -> workTitle w == t)

findCls :: T.Text -> [Classification] -> Maybe Classification
findCls t = find (\c -> clsTitle c == t)

spec :: Spec
spec = describe "Bartleby.Walker" $ do

  describe "shouldWalk" $ do
    it "skips dotfiles when include_dotfiles=False" $
      Walker.shouldWalk False False ".plan" `shouldBe` False

    it "includes dotfiles when include_dotfiles=True" $
      Walker.shouldWalk True  False ".plan" `shouldBe` True

    it "always skips .git regardless of the flag" $ do
      Walker.shouldWalk False False ".git" `shouldBe` False
      Walker.shouldWalk True  False ".git" `shouldBe` False

    it "always skips .DS_Store regardless of the flag" $ do
      Walker.shouldWalk False False ".DS_Store" `shouldBe` False
      Walker.shouldWalk True  False ".DS_Store" `shouldBe` False

    it "always skips .hg, .svn, .bzr even with include_dotfiles=True" $
      map (Walker.shouldWalk True False) [".hg", ".svn", ".bzr"]
        `shouldBe` [False, False, False]

    it "regular files are walked in either mode" $ do
      Walker.shouldWalk False False "regular.txt" `shouldBe` True
      Walker.shouldWalk True  False "regular.txt" `shouldBe` True

    it "root reservations apply regardless of dotfile flag" $ do
      Walker.shouldWalk False True "catalog"        `shouldBe` False
      Walker.shouldWalk True  True "catalog"        `shouldBe` False
      Walker.shouldWalk True  True "bartleby.conf"  `shouldBe` False

    it "non-root: catalog is just a normal directory name" $
      Walker.shouldWalk False False "catalog" `shouldBe` True

  describe "walkLibrary with the dotfiles fixture" $ do
    let dotFixture  = "test/fixtures/walker/dotfiles"
        hideConfig  = defaultConfig { cfgIncludeDotfiles = False }
        showConfig  = defaultConfig { cfgIncludeDotfiles = True }

    it "skips .plan when include_dotfiles=False" $ do
      (Library root, _) <- Walker.walkLibrary dotFixture hideConfig
      map workTitle (clsWorks root) `shouldNotContain` [".plan"]
      map workTitle (clsWorks root) `shouldContain`    ["regular.txt"]

    it "includes .plan when include_dotfiles=True" $ do
      (Library root, _) <- Walker.walkLibrary dotFixture showConfig
      map workTitle (clsWorks root) `shouldContain` [".plan"]
      map workTitle (clsWorks root) `shouldContain` ["regular.txt"]

  describe "walkLibrary on the basic fixture" $ do

    it "walks without fatal errors" $ do
      (_, _) <- Walker.walkLibrary fixtureRoot defaultConfig
      pure ()

    it "produces the expected root classification title (library basename)" $ do
      (Library root, _) <- Walker.walkLibrary fixtureRoot defaultConfig
      clsTitle root `shouldBe` "basic"

    it "recipes/ is a classification with bcard-supplied title + description" $ do
      (Library root, _) <- Walker.walkLibrary fixtureRoot defaultConfig
      case findCls "Recipes" (clsSubs root) of
        Nothing -> expectationFailure "expected sub-classification 'Recipes'"
        Just c  -> do
          clsDescription c `shouldBe` "Things with flour and heat."

    it "notes/ is a classification using its dirname" $ do
      (Library root, _) <- Walker.walkLibrary fixtureRoot defaultConfig
      case findCls "notes" (clsSubs root) of
        Nothing -> expectationFailure "expected sub-classification 'notes'"
        Just c  -> clsDescription c `shouldBe` ""

    it "cheesecake.jpg is a type-I work using bcard metadata" $ do
      (Library root, _) <- Walker.walkLibrary fixtureRoot defaultConfig
      let Just recipes = findCls "Recipes" (clsSubs root)
      case findWork "Cheesecake" (clsWorks recipes) of
        Nothing -> expectationFailure "expected work 'Cheesecake'"
        Just w  -> do
          workKind w `shouldBe` WorkFile TypeI
          workCreated w `shouldBe` fromGregorian 2026 4 18
          workDescription w `shouldBe` "Classic New York style."

    it "snickerdoodles/ is a directory-work (opaque, type 1)" $ do
      (Library root, _) <- Walker.walkLibrary fixtureRoot defaultConfig
      let Just recipes = findCls "Recipes" (clsSubs root)
      case findWork "Snickerdoodles" (clsWorks recipes) of
        Nothing -> expectationFailure "expected work 'Snickerdoodles'"
        Just w  -> do
          workKind w `shouldBe` WorkDirectory
          workCreated w `shouldBe` fromGregorian 2026 4 20
          workSize w > 0 `shouldBe` True  -- recursive size non-zero

    it "auto-guesses text work metadata from the file" $ do
      (Library root, _) <- Walker.walkLibrary fixtureRoot defaultConfig
      let Just notes = findCls "notes" (clsSubs root)
      case findWork "hello.txt" (clsWorks notes) of
        Nothing -> expectationFailure "expected work 'hello.txt' (auto-guessed from filename)"
        Just w  -> do
          workKind w `shouldBe` WorkFile Type0
          -- First paragraph becomes the description.
          workDescription w `shouldBe` "This is the first paragraph of hello."

    it "warns on an orphan bcard" $ do
      (_, ws) <- Walker.walkLibrary fixtureRoot defaultConfig
      let orphanWs = filter (\w -> T.pack "orphan card" `T.isInfixOf` wMessage w) ws
      length orphanWs `shouldBe` 1

    it "populates recursive cached fields on classifications" $ do
      (Library root, _) <- Walker.walkLibrary fixtureRoot defaultConfig
      -- root has no direct works; all works live in sub-classifications
      let Just recipes = findCls "Recipes" (clsSubs root)
      -- Recipes contains 2 works: cheesecake (file) + snickerdoodles (dir)
      clsTotalWorks recipes `shouldBe` 2
      -- root total = recipes (2) + notes (1)
      clsTotalWorks root `shouldBe` 3

    it "a work-directory is opaque (its interior is not cataloged)" $ do
      (Library root, _) <- Walker.walkLibrary fixtureRoot defaultConfig
      let Just recipes = findCls "Recipes" (clsSubs root)
      -- photo.jpg and recipe.txt live inside the Snickerdoodles
      -- work-directory; they must not appear as separate entries
      -- anywhere in the recipes subtree.
      findWork "photo.jpg"  (clsWorks recipes) `shouldBe` Nothing
      findWork "recipe.txt" (clsWorks recipes) `shouldBe` Nothing
      -- No phantom sub-classification leaks out of the work either.
      map clsSourcePath (clsSubs recipes)
        `shouldNotContain` ["recipes/snickerdoodles"]

    it "warns on .bcard files nested inside a work-directory" $ do
      (_, ws) <- Walker.walkLibrary fixtureRoot defaultConfig
      let nested = filter
            (\w -> T.pack "inside work-directory"
                     `T.isInfixOf` wMessage w) ws
      -- The fixture contains recipes/snickerdoodles/photo.jpg.bcard
      -- nested inside the Snickerdoodles work-directory.
      length nested `shouldSatisfy` (>= 1)
      -- The warning's path points at the nested bcard itself.
      map wPath nested
        `shouldContain` ["recipes/snickerdoodles/photo.jpg.bcard"]

    it "nested bcards do not leak into the outer work's metadata" $ do
      (Library root, _) <- Walker.walkLibrary fixtureRoot defaultConfig
      let Just recipes = findCls "Recipes" (clsSubs root)
      case findWork "Snickerdoodles" (clsWorks recipes) of
        Nothing -> expectationFailure "expected work 'Snickerdoodles'"
        Just w  -> do
          -- Title, kind, and description still come from the outer
          -- recipes/snickerdoodles.bcard sibling, not from the
          -- nested recipes/snickerdoodles/photo.jpg.bcard.
          workTitle w        `shouldBe` "Snickerdoodles"
          workKind w         `shouldBe` WorkDirectory
          workDescription w  `shouldBe` "My grandmother's recipe."

    it "sorts sub-classifications by directory name (deterministic)" $ do
      (Library root, _) <- Walker.walkLibrary fixtureRoot defaultConfig
      -- walker sorts by filesystem entry name, not display title.
      map clsSourcePath (clsSubs root) `shouldBe` sort (map clsSourcePath (clsSubs root))
