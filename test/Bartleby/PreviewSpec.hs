module Bartleby.PreviewSpec (spec) where

import qualified Bartleby.Preview as Preview
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BS8
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Test.Hspec
import Test.QuickCheck

spec :: Spec
spec = do

  describe "Bartleby.Preview.utf8SafePrefix" $ do

    it "returns the full text when input is shorter than limit" $ do
      let bs = BS8.pack "hello"
      Preview.utf8SafePrefix 100 bs `shouldBe` Right (T.pack "hello")

    it "truncates cleanly at a byte boundary inside ASCII" $ do
      let bs = BS8.pack "abcdefghij"
      Preview.utf8SafePrefix 5 bs `shouldBe` Right (T.pack "abcde")

    it "does not split a multi-byte UTF-8 codepoint" $ do
      -- 'é' encodes as two bytes: 0xC3 0xA9. Truncating at offset 1
      -- would split it; we expect the partial byte to be dropped.
      let bs = TE.encodeUtf8 (T.pack "caf\xE9")    -- "café" (c a f é)
      -- Encoded byte layout: 63 61 66 c3 a9 (5 bytes)
      -- Truncate at 4 bytes → we must drop the leading 0xC3 of é
      Preview.utf8SafePrefix 4 bs `shouldBe` Right (T.pack "caf")

    it "preserves a complete multi-byte codepoint when room allows" $ do
      let bs = TE.encodeUtf8 (T.pack "caf\xE9")
      Preview.utf8SafePrefix 5 bs `shouldBe` Right (T.pack "caf\xE9")

    it "handles empty input" $
      Preview.utf8SafePrefix 100 BS.empty `shouldBe` Right T.empty

    it "handles zero limit" $
      Preview.utf8SafePrefix 0 (BS8.pack "anything") `shouldBe` Right T.empty

    it "property: result re-encodes to ≤ maxBytes bytes" $
      property $ \(NonNegative n) (s :: String) ->
        let bs = TE.encodeUtf8 (T.pack s)
         in case Preview.utf8SafePrefix n bs of
              Right t  -> BS.length (TE.encodeUtf8 t) <= n
              Left _   -> True

    it "property: result is a prefix of the original text when input fits" $
      property $ \(s :: String) ->
        let bs = TE.encodeUtf8 (T.pack s)
            n  = BS.length bs
         in case Preview.utf8SafePrefix n bs of
              Right t -> t == T.pack s
              Left _  -> False

  describe "Bartleby.Preview.firstParagraph" $ do

    it "returns the entire text when no blank line is present" $
      Preview.firstParagraph (T.pack "hello\nworld")
        `shouldBe` T.pack "hello\nworld"

    it "stops at the first blank line" $
      Preview.firstParagraph (T.pack "hello\nmore\n\nsecond para")
        `shouldBe` T.pack "hello\nmore"

    it "skips leading blank lines" $
      Preview.firstParagraph (T.pack "\n\n\nhello\n\nmore")
        `shouldBe` T.pack "hello"

    it "normalizes \\r\\n line endings" $
      Preview.firstParagraph (T.pack "hello\r\nmore\r\n\r\nskipped")
        `shouldBe` T.pack "hello\nmore"

    it "normalizes bare \\r line endings" $
      Preview.firstParagraph (T.pack "hello\rmore\r\rskipped")
        `shouldBe` T.pack "hello\nmore"

    it "empty input yields empty output" $
      Preview.firstParagraph (T.pack "") `shouldBe` T.pack ""

    it "only blank lines yields empty output" $
      Preview.firstParagraph (T.pack "\n\n\n\n") `shouldBe` T.pack ""

    it "property: never contains a blank-line sequence" $
      property $ \(s :: String) ->
        let result = Preview.firstParagraph (T.pack s)
         in not (T.pack "\n\n" `T.isInfixOf` result)
