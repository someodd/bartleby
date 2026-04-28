-- | Orchestrate a bartleby build: read config, walk the library,
-- render gophermaps and atom feeds, write everything under
-- @<library>/catalog/@ via a @catalog.tmp/@ swap.
module Bartleby.Pipeline
  ( run
  ) where

import qualified Bartleby.Atom as Atom
import qualified Bartleby.Config as Config
import qualified Bartleby.Gophermap as Gophermap
import qualified Bartleby.Walker as Walker
import Bartleby.Types

import Control.Monad (forM_)
import qualified Data.ByteString as BS
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory
  ( createDirectoryIfMissing
  , doesFileExist
  , removePathForcibly
  , renameDirectory
  )
import System.Exit (ExitCode (..))
import System.FilePath ((</>), takeDirectory)
import System.IO (hPutStrLn, stderr)

-- | Run bartleby on a library directory. Returns 'ExitSuccess' on a
-- successful build; 'ExitFailure' 1 on any fatal error (missing
-- config, unwritable catalog, etc.). Warnings are printed to stderr
-- and do not change the exit code.
run :: FilePath -> IO ExitCode
run libraryRoot = do
  let confPath = libraryRoot </> "bartleby.conf"
  confExists <- doesFileExist confPath
  if not confExists
    then do
      hPutStrLn stderr $
        "bartleby: I would prefer not to catalog.\n"
        ++ "          '" ++ confPath ++ "' is absent."
      pure (ExitFailure 1)
    else do
      bs <- BS.readFile confPath
      case Config.parseConfig bs of
        Left err -> do
          hPutStrLn stderr $ "bartleby: " ++ err
          pure (ExitFailure 1)
        Right (config, configWarnings) ->
          build libraryRoot config configWarnings

build :: FilePath -> Config -> [Warning] -> IO ExitCode
build libraryRoot config configWarnings = do
  (lib, walkWarnings) <- Walker.walkLibrary libraryRoot config
  let renderMap = renderLibrary config lib
      tmpDir    = libraryRoot </> "catalog.tmp"
      catDir    = libraryRoot </> "catalog"

  -- Clean any stale tmp from a prior crashed run.
  removePathForcibly tmpDir
  createDirectoryIfMissing True tmpDir
  writeCatalog tmpDir renderMap

  -- Swap into place: rm old catalog/, rename tmp → catalog/.
  removePathForcibly catDir
  renameDirectory tmpDir catDir

  forM_ (configWarnings ++ walkWarnings) printWarning
  pure ExitSuccess

------------------------------------------------------------------------
-- Rendering

-- | Collect every classification in pre-order.
allClassifications :: Classification -> [Classification]
allClassifications cls = cls : concatMap allClassifications (clsSubs cls)

-- | Build the full map of catalog-relative paths → file content.
renderLibrary :: Config -> Library -> Map FilePath Text
renderLibrary config (Library root) =
  Map.fromList (concatMap (renderOne config) (allClassifications root))

renderOne :: Config -> Classification -> [(FilePath, Text)]
renderOne config cls =
  [ (gophermapPath, Gophermap.renderClassification config cls)
  , (feedPath,      Atom.renderFeed config cls)
  ]
  where
    sourcePath  = clsSourcePath cls
    mapName     = T.unpack (cfgGophermapFilename config)
    gophermapPath = case sourcePath of
      "" -> mapName
      p  -> p </> mapName
    feedPath = case sourcePath of
      "" -> "feed.xml"
      p  -> p </> "feed.xml"

------------------------------------------------------------------------
-- Writing

writeCatalog :: FilePath -> Map FilePath Text -> IO ()
writeCatalog catDir files =
  forM_ (Map.toList files) $ \(relPath, content) -> do
    let fullPath  = catDir </> relPath
        parentDir = takeDirectory fullPath
    createDirectoryIfMissing True parentDir
    TIO.writeFile fullPath content

------------------------------------------------------------------------
-- Warnings

printWarning :: Warning -> IO ()
printWarning (Warning path msg) =
  hPutStrLn stderr $
    "bartleby: warning: " ++ path ++ ": " ++ T.unpack msg
