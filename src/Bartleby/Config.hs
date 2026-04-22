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

import Bartleby.Types
import qualified Data.Aeson as Aeson
import Data.Aeson (Value (..))
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import Data.ByteString (ByteString)
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
  let warnings =
        [ Warning "bartleby.conf" ("unknown field: " <> Key.toText k)
        | k <- KeyMap.keys obj
        , Key.toText k `notElem` knownFields
        ]
  pure ( Config
           { cfgHostname         = hostname
           , cfgPort             = port
           , cfgSelector         = normalizeSelector rawSel
           , cfgRecentCount      = recent
           , cfgFeedCount        = feed
           , cfgTextPreviewBytes = preview
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

-- | Normalize a selector string: ensure a leading slash, strip
-- trailing slashes, preserve \"\/\" as the root form.
normalizeSelector :: Text -> Selector
normalizeSelector raw =
  let prefixed = case T.uncons raw of
        Just ('/', _) -> raw
        _             -> T.cons '/' raw
      stripped = T.dropWhileEnd (== '/') prefixed
  in Selector (if T.null stripped then "/" else stripped)
