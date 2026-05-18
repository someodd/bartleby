module Main (main) where

import qualified Bartleby.Pipeline as Pipeline
import Data.Version (showVersion)
import qualified Paths_bartleby as P (version)
import System.Environment (getArgs)
import System.Exit (ExitCode (..), exitWith)
import System.IO (hPutStr, hPutStrLn, stderr)

versionString :: String
versionString = "bartleby " ++ showVersion P.version

usage :: String
usage = unlines
  [ "bartleby [PATH]"
  , ""
  , "Arguments:"
  , "  PATH        Library directory containing bartleby.conf"
  , "              (default: current directory)."
  , ""
  , "Options:"
  , "  --version   Print version and exit."
  , "  --help      Print usage and exit."
  ]

main :: IO ()
main = do
  args <- getArgs
  case args of
    ["--version"] -> putStrLn versionString
    ["-V"]        -> putStrLn versionString
    ["--help"]    -> putStr usage
    ["-h"]        -> putStr usage
    []            -> Pipeline.run "." >>= exitWith
    [path]        -> Pipeline.run path >>= exitWith
    _             -> do
      hPutStrLn stderr "bartleby: I would prefer not to parse those arguments."
      hPutStr stderr usage
      exitWith (ExitFailure 1)
