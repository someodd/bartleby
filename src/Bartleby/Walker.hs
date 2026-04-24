-- | Walk a library directory and build the Library model.
--
-- Responsibilities:
--
-- * List each directory's entries in a deterministic (sorted) order.
-- * Pair each @\<name\>.bcard@ file with its sibling target; warn on orphans.
-- * Decide, for each directory, whether it is a work (has a bcard with
--   @classification@ absent or false) or a classification (no bcard, or a
--   bcard with @classification: true@).
-- * Auto-guess metadata for bcard-less files.
-- * Read UTF-8-safe text previews for text works; compute first-paragraph
--   description fallbacks.
-- * Compute each directory-work's recursive byte size (the one exception
--   to the "opaque" rule).
-- * Populate cached recursive counts and size on each 'Classification'
--   so the renderer never re-walks the tree.
module Bartleby.Walker
  ( walkLibrary
  , itemTypeFor
  ) where

import Bartleby.BCard (parseBCard)
import qualified Bartleby.Preview as Preview
import Bartleby.Types

import Control.Monad (forM)
import qualified Data.ByteString as BS
import Data.Char (toLower)
import Data.List (isSuffixOf, sort)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock (utctDay)
import System.Directory
  ( canonicalizePath
  , doesDirectoryExist
  , doesFileExist
  , getFileSize
  , getModificationTime
  , listDirectory
  , pathIsSymbolicLink
  )
import System.FilePath ((</>), takeExtension, takeFileName)

-- | Walk a library directory and produce a fully-populated 'Library'.
-- The root directory's basename becomes the root classification's title.
walkLibrary :: FilePath -> Config -> IO (Library, [Warning])
walkLibrary libraryRoot config = do
  absRoot <- canonicalizePath libraryRoot
  let rootTitle = T.pack (takeFileName absRoot)
  (rootCls, ws) <- walkClassification config absRoot rootTitle "" True Nothing
  pure (Library rootCls, ws)

-- | Map a file extension to a gopher item type.
itemTypeFor :: FilePath -> ItemType
itemTypeFor path = case map toLower (takeExtension path) of
  ".txt"  -> Type0 ; ".md"   -> Type0 ; ".asc"  -> Type0
  ".org"  -> Type0 ; ".rst"  -> Type0 ; ".log"  -> Type0
  ".csv"  -> Type0 ; ".yml"  -> Type0 ; ".yaml" -> Type0
  ".json" -> Type0 ; ".xml"  -> Type0 ; ".ini"  -> Type0
  ".conf" -> Type0 ; ".py"   -> Type0 ; ".hs"   -> Type0
  ".rb"   -> Type0 ; ".js"   -> Type0 ; ".c"    -> Type0
  ".h"    -> Type0 ; ".cpp"  -> Type0 ; ".sh"   -> Type0
  ".gif"  -> TypeG
  ".jpg"  -> TypeI ; ".jpeg" -> TypeI ; ".png"  -> TypeI
  ".webp" -> TypeI ; ".bmp"  -> TypeI ; ".svg"  -> TypeI
  ".wav"  -> TypeS ; ".mp3"  -> TypeS ; ".ogg"  -> TypeS
  ".flac" -> TypeS
  ".html" -> TypeH ; ".htm"  -> TypeH
  _       -> Type9

-- | Whether a filesystem entry name should be descended into.
shouldWalk :: Bool -> String -> Bool
shouldWalk isRoot name
  | take 1 name == "."                    = False  -- dotfile
  | isRoot && name `elem` reservedAtRoot  = False
  | otherwise                             = True
  where
    reservedAtRoot = ["catalog", "catalog.tmp", "bartleby.conf"]

-- | Split a name list into bcards and other entries.
partitionBcards :: [String] -> ([String], [String])
partitionBcards = foldr go ([], [])
  where
    go n (bs, ts)
      | ".bcard" `isSuffixOf` n = (n : bs, ts)
      | otherwise               = (bs, n : ts)

-- | Strip the trailing @.bcard@ to get the target name.
dropBcardSuffix :: String -> String
dropBcardSuffix name = take (length name - length (".bcard" :: String)) name

-- | What a directory entry is, for walker purposes.
data EntryKind = EFile | EDirectory | ESkipSymlinkDir

classifyEntry :: FilePath -> IO EntryKind
classifyEntry path = do
  isLink <- pathIsSymbolicLink path
  isDir  <- doesDirectoryExist path
  case (isLink, isDir) of
    (True,  True)  -> pure ESkipSymlinkDir
    (_,     True)  -> pure EDirectory
    _              -> pure EFile

-- | The core recursive walker.
walkClassification
  :: Config
  -> FilePath     -- ^ absolute path of this directory
  -> Text         -- ^ default title (dirname or library basename at root)
  -> FilePath     -- ^ relative-to-library path (\"\" at root)
  -> Bool         -- ^ is this the library root?
  -> Maybe BCard  -- ^ a @classification: true@ card from the parent (or None)
  -> IO (Classification, [Warning])
walkClassification config dirPath defaultTitle relPath isRoot mClsCard = do
  rawEntries <- listDirectory dirPath
  let entries = sort (filter (shouldWalk isRoot) rawEntries)
      (bcardNames, targetNames) = partitionBcards entries

  -- Read each bcard (may produce parse failures and/or warnings).
  bcardResults <- forM bcardNames $ \bname -> do
    let bpath   = dirPath </> bname
        bRel    = joinRel relPath bname
        tName   = dropBcardSuffix bname
    bs <- BS.readFile bpath
    case parseBCard bRel bs of
      Left err       -> pure (tName, Nothing, [Warning bRel (T.pack err)])
      Right (c, cws) -> pure (tName, Just c, cws)
  let bcardMap       = Map.fromList [(n, c) | (n, Just c, _) <- bcardResults]
      bcardWarnings  = concat [ws | (_, _, ws) <- bcardResults]

  -- Classify each target (File / Directory / Skip).
  targetResults <- forM targetNames $ \tname -> do
    kind <- classifyEntry (dirPath </> tname)
    pure (tname, kind)

  let targetNameSet  = [n | (n, _) <- targetResults]
      orphanWarnings =
        [ Warning (joinRel relPath (dropBcardSuffix b ++ ".bcard"))
                  (T.pack ("orphan card: no sibling '"
                             <> dropBcardSuffix b <> "' found"))
        | b <- bcardNames
        , dropBcardSuffix b `notElem` targetNameSet
        ]

  -- Walk each target.
  walkItems <- forM targetResults $ \(tname, kind) -> do
    let tpath  = dirPath </> tname
        tRel   = joinRel relPath tname
        mcard  = Map.lookup tname bcardMap
    case kind of
      EFile -> do
        (w, ws) <- buildFileWork config tpath tRel (T.pack tname) mcard
        pure (Just (Left w), ws)
      EDirectory -> case isClassificationCard mcard of
        True -> do
          let subTitle = fromMaybe (T.pack tname) (mcard >>= cardTitle)
          (subCls, ws) <-
            walkClassification config tpath subTitle tRel False mcard
          pure (Just (Right subCls), ws)
        False -> case mcard of
          Just _ -> do
            (w, ws) <- buildDirectoryWork config tpath tRel (T.pack tname) mcard
            pure (Just (Left w), ws)
          Nothing -> do
            (subCls, ws) <-
              walkClassification config tpath (T.pack tname) tRel False Nothing
            pure (Just (Right subCls), ws)
      ESkipSymlinkDir -> pure (Nothing, [])

  let works   = [w | (Just (Left  w), _) <- walkItems]
      subs    = [c | (Just (Right c), _) <- walkItems]
      itemWs  = concat [ws | (_, ws) <- walkItems]

      cTitle  = case mClsCard of
                  Just c  -> fromMaybe defaultTitle (cardTitle c)
                  Nothing -> defaultTitle
      cDesc   = fromMaybe "" (mClsCard >>= cardDescription)

      totalW  = length works + sum (map clsTotalWorks subs)
      totalSz = sum (map workSize works) + sum (map clsTotalSize subs)
      allDays = map workUpdated works ++ mapMaybe clsLatestUpdated subs
      latest  = if null allDays then Nothing else Just (maximum allDays)

  pure ( Classification
           { clsTitle         = cTitle
           , clsDescription   = cDesc
           , clsSourcePath    = relPath
           , clsSubs          = subs
           , clsWorks         = works
           , clsTotalWorks    = totalW
           , clsTotalSize     = totalSz
           , clsLatestUpdated = latest
           }
       , bcardWarnings ++ orphanWarnings ++ itemWs
       )

-- | Does this bcard mean "describe the directory as a classification"?
isClassificationCard :: Maybe BCard -> Bool
isClassificationCard (Just c) = cardClassification c == Just True
isClassificationCard Nothing  = False

-- | Build a 'Work' for a sibling file, falling back to auto-guessed
-- metadata where the bcard is silent.
buildFileWork
  :: Config -> FilePath -> FilePath -> Text -> Maybe BCard
  -> IO (Work, [Warning])
buildFileWork config absPath relPath name mcard = do
  sizeBytes <- getFileSize absPath
  mtime     <- getModificationTime absPath
  let mDay     = utctDay mtime
      itype    = itemTypeFor absPath
      title    = fromMaybe name (mcard >>= cardTitle)
      created  = fromMaybe mDay  (mcard >>= cardCreated)
      updated  = fromMaybe created (mcard >>= cardUpdated)
  (desc, preview, ws) <-
    resolveDescriptionAndPreview config absPath relPath itype mcard
  pure
    ( Work
        { workTitle       = title
        , workCreated     = created
        , workUpdated     = updated
        , workDescription = desc
        , workKind        = WorkFile itype
        , workSourcePath  = relPath
        , workSize        = sizeBytes
        , workPreview     = preview
        }
    , ws
    )

-- | Build a 'Work' for a directory that has a @classification: false@
-- (or absent) bcard — a "directory-as-book." Its interior is opaque
-- except for the recursive byte count.
--
-- Any @.bcard@ files found nested inside the work-directory are
-- warned about and otherwise untouched — the user likely meant the
-- directory to be a classification, or the bcard to live one level
-- up. Opacity is preserved; only stderr gains a line.
buildDirectoryWork
  :: Config -> FilePath -> FilePath -> Text -> Maybe BCard
  -> IO (Work, [Warning])
buildDirectoryWork _config absPath relPath name mcard = do
  mtime               <- getModificationTime absPath
  (sz, innerBcards)   <- walkForSizeAndBcards absPath relPath
  let mDay     = utctDay mtime
      title    = fromMaybe name (mcard >>= cardTitle)
      created  = fromMaybe mDay (mcard >>= cardCreated)
      updated  = fromMaybe created (mcard >>= cardUpdated)
      desc     = fromMaybe "" (mcard >>= cardDescription)
      warnings =
        [ Warning bpath
            ("bcard inside work-directory '"
              <> T.pack relPath <> "' is ignored")
        | bpath <- innerBcards
        ]
  pure
    ( Work
        { workTitle       = title
        , workCreated     = created
        , workUpdated     = updated
        , workDescription = desc
        , workKind        = WorkDirectory
        , workSourcePath  = relPath
        , workSize        = sz
        , workPreview     = Nothing
        }
    , warnings
    )

-- | Resolve description and optional preview from the file's text
-- content (for text works) or from the bcard (for non-text works).
resolveDescriptionAndPreview
  :: Config -> FilePath -> FilePath -> ItemType -> Maybe BCard
  -> IO (Text, Maybe Text, [Warning])
resolveDescriptionAndPreview config absPath relPath itype mcard =
  case itype of
    Type0 -> do
      result <- Preview.readPreview (cfgTextPreviewBytes config) absPath
      case result of
        Right txt ->
          let desc = fromMaybe (Preview.firstParagraph txt)
                               (mcard >>= cardDescription)
           in pure (desc, Just txt, [])
        Left err ->
          let desc = fromMaybe "" (mcard >>= cardDescription)
              w    = Warning relPath (T.pack ("text preview: " <> err))
           in pure (desc, Nothing, [w])
    _ ->
      let desc = fromMaybe "" (mcard >>= cardDescription)
       in pure (desc, Nothing, [])

-- | Walk a work-directory to (a) compute its recursive byte size and
-- (b) collect the library-relative paths of any @.bcard@ files nested
-- inside. The caller ('buildDirectoryWork') turns the second list
-- into one warning per entry; opacity is preserved because the
-- bcards are never read.
--
-- Follows file symlinks; skips directory symlinks (same policy as
-- the main walker).
walkForSizeAndBcards
  :: FilePath   -- ^ absolute path of the work directory
  -> FilePath   -- ^ library-relative path of the work directory
  -> IO (Integer, [FilePath])
walkForSizeAndBcards absPath relPath = do
  entries <- listDirectory absPath
  results <- forM entries $ \name -> do
    let abs' = absPath </> name
        rel' = joinRel relPath name
    isLink <- pathIsSymbolicLink abs'
    isDir  <- doesDirectoryExist abs'
    case (isLink, isDir) of
      (True, True) -> pure (0, [])
      (_,    True) -> walkForSizeAndBcards abs' rel'
      _            -> do
        isFile <- doesFileExist abs'
        if isFile
          then do
            sz <- getFileSize abs'
            let bcards = [rel' | ".bcard" `isSuffixOf` name]
            pure (sz, bcards)
          else pure (0, [])
  let (sizes, bcardLists) = unzip results
  pure (sum sizes, concat bcardLists)

-- | Join a relative directory path with a leaf name, handling the
-- root case (relPath = "") cleanly.
joinRel :: FilePath -> FilePath -> FilePath
joinRel "" name = name
joinRel rel name = rel </> name
