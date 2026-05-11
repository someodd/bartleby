-- | Extension-keyed Gopher item-type table.
--
-- Owns the default mapping and the lookup used by 'Bartleby.Walker'.
-- The set of accepted single-character codes for user-supplied
-- mappings (via @item_types@ in @bartleby.conf@) is also defined here.
module Bartleby.ItemTypes
  ( defaultItemTypes
  , lookupItemType
  , parseItemTypeChar
  , acceptedItemTypeChars
  , normalizeExtension
  ) where

import Bartleby.Types (ItemType (..))
import Data.Char (toLower)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import System.FilePath (takeExtension)

-- | The built-in extension → item-type table. Users can extend or
-- override this via the @item_types@ field in @bartleby.conf@; the
-- merged map is stored in 'Bartleby.Types.cfgItemTypes'.
defaultItemTypes :: Map Text ItemType
defaultItemTypes = Map.fromList $
  [ (e, Type0) | e <-
      [ ".txt", ".md", ".asc", ".org", ".rst", ".log"
      , ".csv", ".yml", ".yaml", ".json", ".xml", ".ini"
      , ".conf", ".py", ".hs", ".rb", ".js", ".c"
      , ".h", ".cpp", ".sh"
      ]
  ] ++
  [ (".gif", TypeG) ] ++
  [ (e, TypeI) | e <- [".jpg", ".jpeg", ".png", ".webp", ".bmp", ".svg"] ] ++
  [ (e, TypeS) | e <- [".wav", ".mp3", ".ogg", ".flac"] ] ++
  [ (e, TypeH) | e <- [".html", ".htm"] ]

-- | Look up the item type for a file path. The extension is taken
-- via 'takeExtension' and lowercased; anything not present in the
-- map falls back to 'Type9' (binary).
lookupItemType :: Map Text ItemType -> FilePath -> ItemType
lookupItemType m path =
  Map.findWithDefault Type9 (normalizeExtension (takeExtension path)) m

-- | Normalize an extension string to the form used as a map key:
-- ASCII-lowercased 'Text'. Caller is responsible for ensuring the
-- input is actually an extension (starts with @.@) — used both by
-- the lookup and by the config parser.
normalizeExtension :: String -> Text
normalizeExtension = T.pack . map toLower

-- | The Gopher item-type codes accepted in @item_types@ values.
-- 'Type1' (menu) is included so users can mark CGI scripts or other
-- executables that emit a gopher menu.
acceptedItemTypeChars :: [(Char, ItemType)]
acceptedItemTypeChars =
  [ ('0', Type0)
  , ('1', Type1)
  , ('I', TypeI)
  , ('g', TypeG)
  , ('s', TypeS)
  , ('h', TypeH)
  , ('9', Type9)
  ]

-- | Parse a user-supplied item-type code (e.g. @"0"@, @"I"@). The
-- input must be a single-character string from
-- 'acceptedItemTypeChars'.
parseItemTypeChar :: Text -> Either String ItemType
parseItemTypeChar t = case T.unpack t of
  [c] -> case lookup c acceptedItemTypeChars of
    Just it -> Right it
    Nothing -> Left (unexpected c)
  _ -> Left ("expected a single-character item-type code (one of " ++ valid ++ "), got " ++ show t)
  where
    unexpected c = "unknown item-type code " ++ show c
                ++ "; must be one of " ++ valid
    valid = unwords (map (\(c, _) -> [c]) acceptedItemTypeChars)
