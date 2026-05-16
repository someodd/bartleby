-- | Render a 'Classification' into a gophermap (the catalog page for
-- that classification).
--
-- All line formatting goes through 'Venusia.MenuBuilder' so the wire
-- conventions (tab separators, CRLF endings, item-type characters)
-- are consistent.
module Bartleby.Gophermap
  ( renderClassification
  , formatSize
  , itemTypeChar
  ) where

import Bartleby.Preview (summarizeDescription, summaryLineLength)
import Bartleby.Types

import Data.Function (on)
import Data.List (sortBy)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Calendar (Day, showGregorian)
import Text.Printf (printf)
import qualified Venusia.MenuBuilder as VM

-- | Render the gophermap content for a classification.
--
-- Section order follows library convention: browse-by-classification
-- first, then the works shelved at this level, then @Recent
-- Accessions@ as a secondary view, then the atom feed link, then an
-- escape-hatch link to the raw source directory.
renderClassification :: Config -> Classification -> Text
renderClassification config cls = T.concat
  [ renderHeader cls
  , renderSubClassifications config cls
  , renderWorks config cls
  , renderRecentAccessions config cls
  , renderFeedLink config cls
  , renderSourceDirLink config cls
  ]

------------------------------------------------------------------------
-- Header

renderHeader :: Classification -> Text
renderHeader cls = T.concat
  [ VM.info ""
  , VM.info "  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  , VM.info ("   " <> spacedTitle (clsTitle cls))
  , VM.info "  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  , VM.info ""
  , renderBreadcrumb cls
  , VM.info ("  " <> holdingsLine cls)
  , VM.info ""
  , renderDescriptionLines (clsDescription cls)
  ]

-- | A single info line of slugs from 'clsSourcePath' so readers can
-- see where they are in a deep tree. Empty at the root (no path to
-- show) — same code path, no @if isRoot@.
renderBreadcrumb :: Classification -> Text
renderBreadcrumb cls = case clsSourcePath cls of
  ""   -> ""
  path ->
    let segments = T.splitOn "/" (T.pack path)
    in VM.info ("  " <> T.intercalate " / " segments) <> VM.info ""

spacedTitle :: Text -> Text
spacedTitle = T.intersperse ' '

holdingsLine :: Classification -> Text
holdingsLine cls =
  let n  = clsTotalWorks cls
      m  = length (clsSubs cls)
      sz = clsTotalSize cls
  in if n == 0 && m == 0
       then "Holdings: none"
       else "Holdings: " <> tshow n <> " works"
            <> (if m > 0
                  then ", in " <> tshow m <> " classifications"
                  else "")
            <> (if sz > 0 then " (" <> formatSize sz <> ")" else "")

renderDescriptionLines :: Text -> Text
renderDescriptionLines "" = ""
renderDescriptionLines desc =
  let ls = T.lines (escapeTabs desc)
  in T.concat [VM.info ("  " <> l) | l <- ls] <> VM.info ""

------------------------------------------------------------------------
-- Sections

-- | Top-N recently-updated works drawn from this classification's
-- sub-classifications only — the recursion-flat recency view,
-- complementary to 'renderWorks' (which lists the works directly
-- shelved here). Direct works are excluded by source: the walk
-- starts at 'clsSubs cls', so 'clsWorks cls' is never visited and
-- Class-Here Works can never overlap with Recent.
--
-- Auto-hides via 'null recent' whenever the sub-walk yields nothing
-- (leaves with no subs, parents whose subs are all empty). No
-- separate \"tiny library\" threshold — the dedup removes the
-- duplication that threshold was guarding against.
renderRecentAccessions :: Config -> Classification -> Text
renderRecentAccessions config cls
  | null recent = ""
  | otherwise = T.concat
      [ VM.info "  Recent Accessions"
      , VM.info "  -----------------"
      , T.concat (map (renderWorkLine config) recent)
      , VM.info ""
      ]
  where
    recent = take (cfgRecentCount config) $
      sortBy (flip compare `on` workUpdated)
             (concatMap allWorksRecursive (clsSubs cls))

renderSubClassifications :: Config -> Classification -> Text
renderSubClassifications config cls
  | null (clsSubs cls) = ""
  | otherwise = T.concat
      [ VM.info "  Classifications"
      , VM.info "  ---------------"
      , T.concat (map (renderSubCls config) (clsSubs cls))
      , VM.info ""
      ]

renderWorks :: Config -> Classification -> Text
renderWorks config cls
  | null (clsWorks cls) = ""
  | otherwise = T.concat
      [ VM.info "  Class-Here Works"
      , VM.info "  ----------------"
      , T.concat (map (renderWorkLine config) sortedWorks)
      , VM.info ""
      ]
  where
    sortedWorks =
      sortBy (flip compare `on` workUpdated) (clsWorks cls)

renderFeedLink :: Config -> Classification -> Text
renderFeedLink config cls =
  let base = unSelector (cfgSelector config) <> "/catalog/"
      sel  = case clsSourcePath cls of
        ""   -> base <> "feed.xml"
        path -> base <> T.pack path <> "/feed.xml"
  in VM.text "Atom feed" sel (cfgHostname config) (cfgPort config)

-- | Escape-hatch link to the raw directory the gopher daemon serves
-- alongside @catalog/@. Lets readers step outside the curated view
-- to see sidecar @.bcard@s, non-cataloged files, and the contents of
-- work-directories.
renderSourceDirLink :: Config -> Classification -> Text
renderSourceDirLink config cls =
  let sel = case clsSourcePath cls of
        ""   -> unSelector (cfgSelector config) <> "/"
        path -> unSelector (cfgSelector config) <> "/" <> T.pack path <> "/"
  in VM.directory "Browse source directory" sel
                  (cfgHostname config) (cfgPort config)

------------------------------------------------------------------------
-- Entries

renderWorkLine :: Config -> Work -> Text
renderWorkLine config w =
  let display = escapeTabs $
        workTitle w
          <> " (" <> dateText (workUpdated w)
          <> ", " <> formatSize (workSize w)
          <> ")"
      sel = unSelector (cfgSelector config) <> "/" <> T.pack (workSourcePath w)
      tch = itemTypeChar (workKind w)
      line = VM.item tch display sel (cfgHostname config) (cfgPort config)
      desc = renderDescInfoLine (workDescription w)
  in line <> desc

renderSubCls :: Config -> Classification -> Text
renderSubCls config sub =
  let n  = clsTotalWorks sub
      sz = clsTotalSize sub
      pluralWorks = if n == 1 then " work" else " works"
      updPart = case clsLatestUpdated sub of
        Nothing -> ""
        Just d  -> ", updated " <> dateText d
      szPart = if sz > 0 then ", " <> formatSize sz else ""
      display = escapeTabs $
        clsTitle sub <> " (" <> tshow n <> pluralWorks <> updPart <> szPart <> ")"
      sel = unSelector (cfgSelector config)
              <> "/catalog/"
              <> T.pack (clsSourcePath sub)
              <> "/"
      line = VM.directory display sel (cfgHostname config) (cfgPort config)
      desc = renderDescInfoLine (clsDescription sub)
  in line <> desc

-- | One info line showing a description, shaped by
-- 'summarizeDescription' (whitespace collapsed, truncated to
-- 'summaryLineLength' codepoints with @...@). Omitted entirely
-- when the description is empty.
renderDescInfoLine :: Text -> Text
renderDescInfoLine "" = ""
renderDescInfoLine desc =
  VM.info ("  " <> summarizeDescription summaryLineLength desc)

------------------------------------------------------------------------
-- Helpers

allWorksRecursive :: Classification -> [Work]
allWorksRecursive cls =
  clsWorks cls ++ concatMap allWorksRecursive (clsSubs cls)

escapeTabs :: Text -> Text
escapeTabs = T.replace "\t" "  "

dateText :: Day -> Text
dateText = T.pack . showGregorian

tshow :: Show a => a -> Text
tshow = T.pack . show

-- | Gopher item-type character for a 'WorkKind'.
itemTypeChar :: WorkKind -> Char
itemTypeChar WorkDirectory = '1'
itemTypeChar (WorkFile t)  = case t of
  Type0 -> '0'
  Type1 -> '1'
  TypeI -> 'I'
  TypeG -> 'g'
  TypeS -> 's'
  TypeH -> 'h'
  Type9 -> '9'

-- | 1024-based size formatter. Bytes below 1024 display as @N B@;
-- anything else scales to the largest unit ≤ the value with one
-- decimal (K\/M\/G).
formatSize :: Integer -> Text
formatSize bytes
  | bytes < kb = T.pack (show bytes) <> " B"
  | bytes < mb = fmt "%.1f K" (fromIntegral bytes / fromIntegral kb :: Double)
  | bytes < gb = fmt "%.1f M" (fromIntegral bytes / fromIntegral mb :: Double)
  | otherwise  = fmt "%.1f G" (fromIntegral bytes / fromIntegral gb :: Double)
  where
    kb = 1024 :: Integer
    mb = kb * 1024
    gb = mb * 1024
    fmt :: String -> Double -> Text
    fmt f x = T.pack (printf f x)
