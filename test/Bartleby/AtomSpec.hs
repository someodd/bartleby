module Bartleby.AtomSpec (spec) where

import qualified Bartleby.Atom as Atom
import Bartleby.Types
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Calendar (fromGregorian)
import Test.Hspec

defaultConfig :: Config
defaultConfig = Config
  { cfgHostname          = "gopher.example.com"
  , cfgPort              = 70
  , cfgSelector          = Selector "/library"
  , cfgRecentCount       = 10
  , cfgFeedCount         = 50
  , cfgTextPreviewBytes  = 4096
  , cfgGophermapFilename = ".gophermap"
  }

emptyCls :: Text -> Classification
emptyCls t = Classification
  { clsTitle         = t
  , clsDescription   = ""
  , clsSourcePath    = ""
  , clsSubs          = []
  , clsWorks         = []
  , clsTotalWorks    = 0
  , clsTotalSize     = 0
  , clsLatestUpdated = Nothing
  }

textWork :: Work
textWork = Work
  { workTitle       = "Hello"
  , workCreated     = fromGregorian 2026 4 18
  , workUpdated     = fromGregorian 2026 4 20
  , workDescription = "A short note."
  , workKind        = WorkFile Type0
  , workSourcePath  = "notes/hello.txt"
  , workSize        = 123
  , workPreview     = Just "Hello world!\n"
  }

imageWork :: Work
imageWork = Work
  { workTitle       = "Cat"
  , workCreated     = fromGregorian 2026 1 1
  , workUpdated     = fromGregorian 2026 1 1
  , workDescription = ""
  , workKind        = WorkFile TypeI
  , workSourcePath  = "photos/cat.jpg"
  , workSize        = 50000
  , workPreview     = Nothing
  }

spec :: Spec
spec = do

  describe "xmlEscape" $ do
    it "escapes &"  $ Atom.xmlEscape "a&b"  `shouldBe` "a&amp;b"
    it "escapes <"  $ Atom.xmlEscape "a<b"  `shouldBe` "a&lt;b"
    it "escapes >"  $ Atom.xmlEscape "a>b"  `shouldBe` "a&gt;b"
    it "escapes \"" $ Atom.xmlEscape "a\"b" `shouldBe` "a&quot;b"
    it "escapes '"  $ Atom.xmlEscape "a'b"  `shouldBe` "a&apos;b"
    it "does not double-escape" $
      Atom.xmlEscape "&amp;" `shouldBe` "&amp;amp;"  -- literal & becomes &amp;
    it "handles mixed specials" $
      Atom.xmlEscape "<a>&'\"" `shouldBe` "&lt;a&gt;&amp;&apos;&quot;"

  describe "cdataWrap" $ do
    it "wraps plain text" $
      Atom.cdataWrap "hello" `shouldBe` "<![CDATA[hello]]>"
    it "splits embedded ]]> safely" $
      Atom.cdataWrap "a]]>b"
        `shouldBe` "<![CDATA[a]]]]><![CDATA[>b]]>"
    it "handles empty input" $
      Atom.cdataWrap "" `shouldBe` "<![CDATA[]]>"

  describe "renderFeed" $ do

    it "renders an empty feed with epoch updated" $ do
      let out = Atom.renderFeed defaultConfig (emptyCls "empty")
      out `shouldSatisfy` T.isInfixOf (T.pack "<feed ")
      out `shouldSatisfy` T.isInfixOf (T.pack "1970-01-01T00:00:00Z")
      out `shouldSatisfy` T.isInfixOf (T.pack "<title>empty</title>")
      out `shouldSatisfy` T.isInfixOf
        (T.pack "gopher://gopher.example.com:70/1/library/catalog/")

    it "omits <subtitle> when description is empty" $ do
      let out = Atom.renderFeed defaultConfig (emptyCls "x")
      out `shouldSatisfy` (not . T.isInfixOf (T.pack "<subtitle"))

    it "emits <subtitle> when description is present" $ do
      let cls = (emptyCls "x") { clsDescription = "Hello world" }
          out = Atom.renderFeed defaultConfig cls
      out `shouldSatisfy` T.isInfixOf (T.pack "<subtitle>Hello world</subtitle>")

    it "renders a text-work entry with CDATA content preview" $ do
      let cls = (emptyCls "x") { clsWorks = [textWork] }
          out = Atom.renderFeed defaultConfig cls
      out `shouldSatisfy` T.isInfixOf (T.pack "<title>Hello</title>")
      out `shouldSatisfy` T.isInfixOf (T.pack "<published>2026-04-18T00:00:00Z</published>")
      out `shouldSatisfy` T.isInfixOf (T.pack "<updated>2026-04-20T00:00:00Z</updated>")
      out `shouldSatisfy` T.isInfixOf (T.pack "length=\"123\"")
      out `shouldSatisfy` T.isInfixOf (T.pack "<![CDATA[Hello world!")

    it "text work without preview produces no <content>" $ do
      let w   = textWork { workPreview = Nothing }
          cls = (emptyCls "x") { clsWorks = [w] }
          out = Atom.renderFeed defaultConfig cls
      out `shouldSatisfy` (not . T.isInfixOf (T.pack "<content"))

    it "image work produces HTML <content> with <img>" $ do
      let cls = (emptyCls "x") { clsWorks = [imageWork] }
          out = Atom.renderFeed defaultConfig cls
      out `shouldSatisfy` T.isInfixOf (T.pack "type=\"html\"")
      out `shouldSatisfy` T.isInfixOf
        (T.pack "<img src=\"gopher://gopher.example.com:70/I/library/photos/cat.jpg\"")

    it "feed updated = max entry updated" $ do
      let cls = (emptyCls "x")
            { clsWorks = [textWork, imageWork { workUpdated = fromGregorian 2000 1 1 }]
            }
          out = Atom.renderFeed defaultConfig cls
      out `shouldSatisfy` T.isInfixOf (T.pack "<updated>2026-04-20T00:00:00Z</updated>")

    it "entries sorted by updated desc (newest first)" $ do
      let older = textWork { workTitle = "Older", workUpdated = fromGregorian 2020 1 1 }
          newer = textWork { workTitle = "Newer", workUpdated = fromGregorian 2026 6 1 }
          cls   = (emptyCls "x") { clsWorks = [older, newer] }
          out   = Atom.renderFeed defaultConfig cls
          -- index of the two titles in the rendered output
          idxNewer = T.length (fst (T.breakOn (T.pack "<title>Newer</title>") out))
          idxOlder = T.length (fst (T.breakOn (T.pack "<title>Older</title>") out))
      idxNewer `shouldSatisfy` (< idxOlder)
