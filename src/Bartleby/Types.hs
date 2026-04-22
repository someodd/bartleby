{-# OPTIONS_GHC -fplugin=LiquidHaskell #-}

-- | Core data types for bartleby.
--
-- All user-facing records (Config, BCard) and the internal model
-- (Work, Classification, Library) live here. Values of these types
-- are plain data — parsing lives in 'Bartleby.Config' and
-- 'Bartleby.BCard'; the walker constructs the Library.
--
-- Refinement type aliases ('Nat', 'Port', 'Bytes') are declared for
-- use in liquidhaskell annotations on numeric defaults and cached
-- counts. Option-B LH scope: demonstrate the wiring; mark a couple of
-- clearly-non-negative values; leave heavy proofs for v2+.
module Bartleby.Types
  ( Warning (..)
  , Selector (..)
  , ItemType (..)
  , WorkKind (..)
  , Config (..)
  , BCard (..)
  , Work (..)
  , Classification (..)
  , Library (..)
    -- * Refinement type aliases (used by LH-refined call sites)
  , defaultPort
  , defaultRecentCount
  , defaultFeedCount
  , defaultTextPreviewBytes
  ) where

import Data.Text (Text)
import Data.Time.Calendar (Day)

------------------------------------------------------------------------
-- Refinement type aliases (LiquidHaskell, option B)
--
-- LiquidHaskell ships a built-in 'Nat' ({v:Int | 0 <= v}); we reuse
-- that. 'Port' and 'Bytes' are our own.

{-@ type Port   = { v:Int     | 1 <= v && v <= 65535 }        @-}
{-@ type Bytes  = { v:Integer | 0 <= v }                      @-}

------------------------------------------------------------------------
-- Numeric defaults (proved by LH to satisfy their refinements)

{-@ defaultPort             :: Port @-}
defaultPort :: Int
defaultPort = 70

{-@ defaultRecentCount      :: Nat @-}
defaultRecentCount :: Int
defaultRecentCount = 10

{-@ defaultFeedCount        :: Nat @-}
defaultFeedCount :: Int
defaultFeedCount = 50

{-@ defaultTextPreviewBytes :: Nat @-}
defaultTextPreviewBytes :: Int
defaultTextPreviewBytes = 4096

-- | A non-fatal issue encountered during a build. Printed to stderr;
-- the build continues.
data Warning = Warning
  { wPath    :: !FilePath
  , wMessage :: !Text
  } deriving (Show, Eq)

-- | A normalized gopher selector path (leading \"\/\", no trailing).
-- Kept as a newtype so we can later refine it (LH: no \"..\") and
-- avoid accidental string concatenation bugs.
newtype Selector = Selector { unSelector :: Text }
  deriving (Show, Eq)

-- | Gopher item type character.
data ItemType
  = Type0  -- ^ plain text
  | Type1  -- ^ directory (menu)
  | TypeI  -- ^ image (non-GIF)
  | TypeG  -- ^ GIF image
  | TypeS  -- ^ sound
  | TypeH  -- ^ HTML
  | Type9  -- ^ binary
  deriving (Show, Eq)

-- | A work is either a typed file or an opaque directory.
data WorkKind
  = WorkFile !ItemType
  | WorkDirectory
  deriving (Show, Eq)

-- | Parsed @bartleby.conf@. The library's own title is derived from
-- the library directory's basename, not stored here.
data Config = Config
  { cfgHostname         :: !Text
  , cfgPort             :: !Int      -- ^ 1..65535
  , cfgSelector         :: !Selector -- ^ normalized
  , cfgRecentCount      :: !Int      -- ^ non-negative
  , cfgFeedCount        :: !Int      -- ^ non-negative
  , cfgTextPreviewBytes :: !Int      -- ^ non-negative
  } deriving (Show, Eq)

-- | Parsed @.bcard@. Every field is optional at the schema level.
-- Atomic validation: any single-field failure discards the whole
-- card and the target falls back to auto-guessed metadata.
data BCard = BCard
  { cardTitle          :: !(Maybe Text)
  , cardCreated        :: !(Maybe Day)
  , cardUpdated        :: !(Maybe Day)
  , cardDescription    :: !(Maybe Text)
  , cardClassification :: !(Maybe Bool)
  } deriving (Show, Eq)

-- | A cataloged entry.
--
-- 'workPreview' holds the UTF-8-safe text prefix for text works
-- (gopher 'Type0'); other kinds have 'Nothing'. Both the atom
-- @<content>@ and the first-paragraph description fallback are
-- derived from this value.
data Work = Work
  { workTitle       :: !Text
  , workCreated     :: !Day
  , workUpdated     :: !Day
  , workDescription :: !Text
  , workKind        :: !WorkKind
  , workSourcePath  :: !FilePath
  , workSize        :: !Integer      -- ^ non-negative (recursive for directory-works)
  , workPreview     :: !(Maybe Text)
  } deriving (Show, Eq)

-- | A classification is a node in the library tree — the recursive
-- structure that the renderer walks.
--
-- The cached fields (@clsTotalWorks@, @clsTotalSize@,
-- @clsLatestUpdated@) are populated bottom-up during Library
-- construction so the renderer never recomputes them.
data Classification = Classification
  { clsTitle         :: !Text
  , clsDescription   :: !Text
  , clsSourcePath    :: !FilePath         -- ^ relative to library root; "" at root
  , clsSubs          :: ![Classification]
  , clsWorks         :: ![Work]
  , clsTotalWorks    :: !Int              -- ^ non-negative, recursive
  , clsTotalSize     :: !Integer          -- ^ non-negative, recursive
  , clsLatestUpdated :: !(Maybe Day)      -- ^ max over recursive works
  } deriving (Show, Eq)

-- | The library is the root 'Classification'. Same type, same
-- renderer — the root is not special.
newtype Library = Library { libRoot :: Classification }
  deriving (Show, Eq)
