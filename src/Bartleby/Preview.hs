-- | UTF-8-safe reading and first-paragraph extraction for text works.
--
-- A text work's content feeds two places:
--
-- * the atom feed's @<content>@ element (the full preview), and
-- * the description fallback when the bcard does not supply one
--   (the first paragraph of the preview).
--
-- Both come from the same read. The tricky bit is that truncating
-- bytes at an arbitrary offset can split a UTF-8 codepoint; this
-- module trims any trailing partial codepoint so decode always
-- succeeds.
module Bartleby.Preview
  ( readPreview
  , utf8SafePrefix
  , firstParagraph
  , summarizeDescription
  ) where

import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import System.IO (IOMode (ReadMode), withBinaryFile)

-- | Read up to @maxBytes@ bytes from @path@ and decode as UTF-8.
-- Trailing partial codepoints are trimmed before decoding.
--
-- Returns @Left@ if decode still fails after trimming — this means
-- the file isn't valid UTF-8 (corrupt or in another encoding).
readPreview :: Int -> FilePath -> IO (Either String Text)
readPreview maxBytes path = do
  bs <- withBinaryFile path ReadMode (\h -> BS.hGet h maxBytes)
  pure (utf8SafePrefix maxBytes bs)

-- | Take up to @maxBytes@ bytes of the given @ByteString@ and decode
-- the result as UTF-8. If the tail of the prefix contains a partial
-- multi-byte codepoint, strip those bytes (at most 4) before
-- decoding.
--
-- The returned @Text@ is always valid UTF-8 and its encoded byte
-- length is ≤ @maxBytes@.
utf8SafePrefix :: Int -> ByteString -> Either String Text
utf8SafePrefix maxBytes bs = go (BS.take maxBytes bs) (0 :: Int)
  where
    -- A valid UTF-8 codepoint is at most 4 bytes; more than four
    -- trim attempts means the decode failure wasn't at the tail.
    go b n
      | n > 4     = Left "utf-8 decode failed (possibly non-UTF-8 or corrupt content)"
      | otherwise = case TE.decodeUtf8' b of
          Right t -> Right t
          Left _
            | not (BS.null b) -> go (BS.init b) (n + 1)
            | otherwise       -> Right T.empty

-- | The first paragraph of a piece of text: the prefix ending just
-- before the first blank line. Leading blank lines are discarded.
-- @\r\n@, @\n@, and bare @\r@ line endings are all recognised.
--
-- If the input has no blank line at all, the whole input is the
-- first paragraph.
firstParagraph :: Text -> Text
firstParagraph input =
  let t1 = T.replace "\r\n" "\n" input
      t2 = T.replace "\r"   "\n" t1
      t3 = T.dropWhile (== '\n') t2
      (para, _rest) = T.breakOn "\n\n" t3
  in para

-- | Shape a work description into a one-line excerpt.
--
-- Collapses every run of whitespace (newlines, tabs, multiple
-- spaces) to a single space, strips leading/trailing whitespace,
-- and truncates to @maxLen@ codepoints with a trailing @...@ if
-- the input was longer.
--
-- This is the single source of truth for the catalog gophermap's
-- per-work info line and the atom feed's @<summary>@ — both want
-- the same one-line excerpt of 'Bartleby.Types.workDescription'.
summarizeDescription :: Int -> Text -> Text
summarizeDescription maxLen desc =
  let collapsed = T.unwords (T.words desc)
  in if T.length collapsed > maxLen
        then T.take (max 0 (maxLen - 3)) collapsed <> "..."
        else collapsed
