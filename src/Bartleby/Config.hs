-- | Parse and validate @bartleby.conf@.
--
-- The config file is YAML with a fixed, small schema. Unknown fields
-- are warned but do not fail the parse. Validation failures (missing
-- hostname, port out of range, negative counts) are fatal — the
-- caller exits 1.
module Bartleby.Config
  ( parseConfig
  , normalizeSelector
  ) where

import Bartleby.ItemTypes (defaultItemTypes, parseItemTypeChar)
import Bartleby.Types
import qualified Data.Aeson as Aeson
import Data.Aeson (Value (..))
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import Data.ByteString (ByteString)
import qualified Data.Char as C
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Yaml as Yaml

-- | The set of keys bartleby.conf recognises. Anything else in the
-- parsed YAML becomes an @unknown field@ warning.
knownFields :: [Text]
knownFields =
  [ "hostname"
  , "port"
  , "selector"
  , "recent_count"
  , "feed_count"
  , "text_preview_bytes"
  , "gophermap_filename"
  , "item_types"
  ]

-- | Parse a bytes blob as bartleby.conf, returning either a fatal
-- parse/validation error or the config plus any non-fatal warnings.
parseConfig :: ByteString -> Either String (Config, [Warning])
parseConfig bs = do
  val <- either (Left . Yaml.prettyPrintParseException) Right
           (Yaml.decodeEither' bs)
  case val of
    Object obj -> fromObject obj
    _          -> Left "bartleby.conf must be a YAML mapping at its top level."

fromObject :: KeyMap.KeyMap Value -> Either String (Config, [Warning])
fromObject obj = do
  hostname <- requireText "hostname"
  port     <- optInt  "port"               70   >>= validatePort
  rawSel   <- optText "selector"           "/"
  recent   <- optInt  "recent_count"       10   >>= nonNeg "recent_count"
  feed     <- optInt  "feed_count"         50   >>= nonNeg "feed_count"
  preview  <- optInt  "text_preview_bytes" 4096 >>= nonNeg "text_preview_bytes"
  mapName  <- optText "gophermap_filename" ".gophermap"
              >>= validateGophermapFilename
  overrides <- parseItemTypesField (look "item_types")
  let warnings =
        [ Warning "bartleby.conf" ("unknown field: " <> Key.toText k)
        | k <- KeyMap.keys obj
        , Key.toText k `notElem` knownFields
        ]
  pure ( Config
           { cfgHostname          = hostname
           , cfgPort              = port
           , cfgSelector          = normalizeSelector rawSel
           , cfgRecentCount       = recent
           , cfgFeedCount         = feed
           , cfgTextPreviewBytes  = preview
           , cfgGophermapFilename = mapName
           , cfgItemTypes         = Map.union overrides defaultItemTypes
           }
       , warnings
       )
  where
    look :: Text -> Maybe Value
    look k = KeyMap.lookup (Key.fromText k) obj

    requireText :: Text -> Either String Text
    requireText k = case look k of
      Nothing -> Left ("required field '" ++ T.unpack k ++ "' is missing")
      Just v  -> fromJ k v

    optText :: Text -> Text -> Either String Text
    optText k def = maybe (Right def) (fromJ k) (look k)

    optInt :: Text -> Int -> Either String Int
    optInt k def = maybe (Right def) (fromJ k) (look k)

    fromJ :: Aeson.FromJSON a => Text -> Value -> Either String a
    fromJ k v = case Aeson.fromJSON v of
      Aeson.Success x -> Right x
      Aeson.Error msg -> Left ("field '" ++ T.unpack k ++ "': " ++ msg)

validatePort :: Int -> Either String Int
validatePort p
  | p >= 1 && p <= 65535 = Right p
  | otherwise            = Left ("port " ++ show p ++ " out of range 1..65535")

nonNeg :: Text -> Int -> Either String Int
nonNeg k n
  | n >= 0    = Right n
  | otherwise = Left ("field '" ++ T.unpack k ++ "' must be >= 0")

-- | Validate a gophermap filename: non-empty, no path separators, not
-- exactly @.@ or @..@. The default is @\".gophermap\"@; users on
-- gophernicus, Pituophis, or Bucktooth should set @gophermap@.
validateGophermapFilename :: Text -> Either String Text
validateGophermapFilename name
  | T.null name      = Left "gophermap_filename must not be empty"
  | name == "."      = Left "gophermap_filename must not be '.'"
  | name == ".."     = Left "gophermap_filename must not be '..'"
  | T.any bad name   = Left "gophermap_filename must not contain '/', '\\', or NUL"
  | otherwise        = Right name
  where
    bad c = c == '/' || c == '\\' || c == '\0'

-- | Parse the @item_types@ field. Absent → empty (caller merges with
-- the built-in defaults). Anything other than a YAML mapping is a
-- fatal parse error; per-entry validation rejects bad keys (must
-- start with @.@, no path separators) and bad values (must be a
-- single-character item-type code in @0 I g s h 9@; @1@ is
-- specifically rejected as a directory marker).
parseItemTypesField :: Maybe Value -> Either String (Map Text ItemType)
parseItemTypesField Nothing  = Right Map.empty
parseItemTypesField (Just v) = case v of
  Object kv ->
    Map.fromList <$> mapM parseEntry (KeyMap.toList kv)
  _ ->
    Left "field 'item_types': must be a YAML mapping of \".ext\" → \"<type-char>\""
  where
    parseEntry (k, val) = do
      let rawKey = Key.toText k
      ext <- validateExtKey rawKey
      itype <- case val of
        String s -> withKey rawKey (parseItemTypeChar s)
        _        -> Left ("field 'item_types': value for key "
                          ++ show (T.unpack rawKey)
                          ++ " must be a string")
      Right (ext, itype)

    withKey :: Text -> Either String a -> Either String a
    withKey k = either
      (\msg -> Left ("field 'item_types' key "
                     ++ show (T.unpack k) ++ ": " ++ msg))
      Right

-- | Validate an extension key from @item_types@. Returns the
-- lowercased form for storage. Rejects empty strings, keys without
-- a leading dot, and keys containing path separators or NUL.
validateExtKey :: Text -> Either String Text
validateExtKey raw
  | T.null raw            = Left "field 'item_types': extension key must not be empty"
  | T.head raw /= '.'     = Left ("field 'item_types': extension key "
                                  ++ show (T.unpack raw)
                                  ++ " must start with '.'")
  | T.length raw < 2      = Left ("field 'item_types': extension key "
                                  ++ show (T.unpack raw)
                                  ++ " must be more than just '.'")
  | T.any badChar raw     = Left ("field 'item_types': extension key "
                                  ++ show (T.unpack raw)
                                  ++ " must not contain '/', '\\', or NUL")
  | otherwise             = Right (T.map C.toLower raw)
  where
    badChar c = c == '/' || c == '\\' || c == '\0'

-- | Normalize a selector string: ensure a leading slash, strip
-- trailing slashes, preserve \"\/\" as the root form.
normalizeSelector :: Text -> Selector
normalizeSelector raw =
  let prefixed = case T.uncons raw of
        Just ('/', _) -> raw
        _             -> T.cons '/' raw
      stripped = T.dropWhileEnd (== '/') prefixed
  in Selector (if T.null stripped then "/" else stripped)
