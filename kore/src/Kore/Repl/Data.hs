{-|
Module      : Kore.Repl.Data
Description : REPL data structures.
Copyright   : (c) Runtime Verification, 2019
License     : NCSA
Maintainer  : vladimir.ciobanu@runtimeverification.com
-}

{-# LANGUAGE TemplateHaskell #-}

module Kore.Repl.Data
    ( ReplCommand (..)
    , helpText
    , ExecutionGraph
    , ReplState (..)
    , lensAxioms, lensClaims, lensClaim
    , lensGraph, lensNode, lensStepper
    , lensOmit
    ) where

import qualified Control.Lens.TH.Rules as Lens
import           Control.Monad.State.Strict
                 ( StateT )
import qualified Data.Graph.Inductive.Graph as Graph

import           Kore.AST.Common
                 ( Variable )
import           Kore.AST.MetaOrObject
                 ( Object )
import           Kore.OnePath.Step
                 ( CommonStrategyPattern )
import           Kore.OnePath.Verification
                 ( Axiom (..) )
import           Kore.OnePath.Verification
                 ( Claim (..) )
import           Kore.Step.Rule
                 ( RewriteRule )
import           Kore.Step.Simplification.Data
                 ( Simplifier )
import qualified Kore.Step.Strategy as Strategy

-- | List of available commands for the Repl. Note that we are always in a proof
-- state. We pick the first available Claim when we initialize the state.
data ReplCommand
    = ShowUsage
    -- ^ This is the default action in case parsing all others fail.
    | Help
    -- ^ Shows the help message.
    | ShowClaim !Int
    -- ^ Show the nth claim.
    | ShowAxiom !Int
    -- ^ Show the nth axiom.
    | Prove !Int
    -- ^ Drop the current proof state and re-initialize for the nth claim.
    | ShowGraph
    -- ^ Show the current execution graph.
    | ProveSteps !Int
    -- ^ Do n proof steps from curent node.
    | SelectNode !Int
    -- ^ Select a different node in the graph.
    | ShowConfig !(Maybe Int)
    -- ^ Show the configuration from the current node.
    | OmitCell !(Maybe String)
    -- ^ Adds or removes cell to omit list, or shows current omit list.
    | ShowLeafs
    -- ^ Show leafs which can continue evaluation and leafs which are stuck
    | ShowRule !(Maybe Int)
    -- ^ Show the rule(s) that got us to this configuration.
    | ShowPrecBranch !(Maybe Int)
    -- ^ Show the first preceding branch
    | ShowChildren !(Maybe Int)
    -- ^ Show direct children of node
    | Exit
    -- ^ Exit the repl.
    deriving (Eq, Show)

-- | Please remember to update this text whenever you update the ADT above.
helpText :: String
helpText =
    "Available commands in the Kore REPL: \n\
    \help                    shows this help message\n\
    \claim <n>               shows the nth claim\n\
    \axiom <n>               shows the nth axiom\n\
    \prove <n>               initializez proof mode for the nth \
                             \claim\n\
    \graph                   shows the current proof graph\n\
    \step [n]                attempts to run 'n' proof steps at\
                             \the current node (n=1 by default)\n\
    \select <n>              select node id 'n' from the graph\n\
    \config [n]              shows the config for node 'n'\
                             \(defaults to current node)\n\
    \omit [cell]             adds or removes cell to omit list\
                             \(defaults to showing the omit list)\n\
    \leafs                   shows unevaluated or stuck leafs\n\
    \rule [n]                shows the rule for node 'n'\
                             \(defaults to current node)\n\
    \prec-branch [n]         shows first preceding branch\n\
                             \(defaults to current node)\n\
    \children [n]            shows direct children of node\n\
                             \(defaults to current node)\n\
    \exit                    exits the repl"

-- Type synonym for the actual type of the execution graph.
type ExecutionGraph =
    Strategy.ExecutionGraph
        (CommonStrategyPattern Object)
        (RewriteRule Object Variable)

-- | State for the rep.
data ReplState level = ReplState
    { axioms  :: [Axiom level]
    -- ^ List of available axioms
    , claims  :: [Claim level]
    -- ^ List of claims to be proven
    , claim   :: Claim level
    -- ^ Currently focused claim in the repl
    , graph   :: ExecutionGraph
    -- ^ Execution graph for the current proof; initialized with root = claim
    , node    :: Graph.Node
    -- ^ Currently selected node in the graph; initialized with node = root
    , omit    :: [String]
    -- ^ The omit list, initially empty
    , stepper :: StateT (ReplState level) Simplifier Bool
    -- ^ Stepper function, it is a partially applied 'verifyClaimStep'
    }

Lens.makeLenses ''ReplState