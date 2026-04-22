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

import Bartleby.Types

import Data.Function (on)
import Data.List (sortBy)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Calendar (Day, showGregorian)
import Text.Printf (printf)
import qualified Venusia.MenuBuilder as VM

-- | Render the gophermap content for a classification.
renderClassification :: Config -> Classification -> Text
renderClassification config cls = T.concat
  [ renderHeader cls
  , renderRecentAccessions config cls
  , renderSubClassifications config cls
  , renderWorks config cls
  , renderFeedLink config cls
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
  , VM.info ("  " <> holdingsLine cls)
  , VM.info ""
  , renderDescriptionLines (clsDescription cls)
  ]

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

renderRecentAccessions :: Config -> Classification -> Text
renderRecentAccessions config cls
  | clsTotalWorks cls <= cfgRecentCount config = ""
  | null recent = ""
  | otherwise = T.concat
      [ VM.info "  Recent Accessions"
      , VM.info "  -----------------"
      , T.concat (map (renderWorkLine config) recent)
      , VM.info ""
      ]
  where
    recent = take (cfgRecentCount config) $
      sortBy (flip compare `on` workUpdated) (allWorksRecursive cls)

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
      [ VM.info "  Works"
      , VM.info "  -----"
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

-- | One info line showing a description, truncated to 70 codepoints
-- with @...@ ellipsis. Newlines collapse to spaces. Tabs replaced.
-- Omitted entirely when the description is empty.
renderDescInfoLine :: Text -> Text
renderDescInfoLine "" = ""
renderDescInfoLine desc =
  let collapsed =
        escapeTabs
          . T.replace "\n" " "
          . T.replace "\r" " "
          $ desc
      truncated
        | T.length collapsed > 70 = T.take 67 collapsed <> "..."
        | otherwise               = collapsed
  in VM.info ("  " <> truncated)

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
