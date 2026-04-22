-- | Parse and validate @.bcard@ sidecar metadata files.
--
-- Every field is schema-level optional. Validation is atomic: if any
-- field fails to parse, the whole card is rejected (Left). Unknown
-- fields do not fail; they produce warnings instead.
--
-- Callers (the walker) interpret a Left as \"skip this card; fall
-- back to auto-guessed metadata\" plus a warning about the path.
module Bartleby.BCard
  ( parseBCard
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

knownFields :: [Text]
knownFields =
  [ "title"
  , "created"
  , "updated"
  , "description"
  , "classification"
  ]

-- | Parse a @.bcard@ byte blob. The path is carried into any
-- warnings emitted so the user can locate typo'd fields.
parseBCard :: FilePath -> ByteString -> Either String (BCard, [Warning])
parseBCard path bs = do
  val <- either (Left . Yaml.prettyPrintParseException) Right
           (Yaml.decodeEither' bs)
  case val of
    Null       -> Right (emptyCard, [])   -- empty file is valid
    Object obj -> fromObject path obj
    _          -> Left (path ++ ": bcard must be a YAML mapping.")

emptyCard :: BCard
emptyCard = BCard Nothing Nothing Nothing Nothing Nothing

fromObject
  :: FilePath
  -> KeyMap.KeyMap Value
  -> Either String (BCard, [Warning])
fromObject path obj = do
  title       <- optField path obj "title"
  created     <- optField path obj "created"
  updated     <- optField path obj "updated"
  description <- optField path obj "description"
  classif     <- optField path obj "classification"
  let warnings =
        [ Warning path ("unknown field: " <> Key.toText k)
        | k <- KeyMap.keys obj
        , Key.toText k `notElem` knownFields
        ]
  pure ( BCard
           { cardTitle          = title
           , cardCreated        = created
           , cardUpdated        = updated
           , cardDescription    = description
           , cardClassification = classif
           }
       , warnings
       )

optField
  :: Aeson.FromJSON a
  => FilePath
  -> KeyMap.KeyMap Value
  -> Text
  -> Either String (Maybe a)
optField path obj k = case KeyMap.lookup (Key.fromText k) obj of
  Nothing -> Right Nothing
  Just v  -> case Aeson.fromJSON v of
    Aeson.Success x -> Right (Just x)
    Aeson.Error msg -> Left (path ++ ": field '" ++ T.unpack k ++ "': " ++ msg)
