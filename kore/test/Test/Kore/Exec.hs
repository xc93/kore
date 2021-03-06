module Test.Kore.Exec
    ( test_exec
    , test_execPriority
    , test_search
    , test_searchPriority
    , test_searchExeedingBreadthLimit
    , test_execGetExitCode
    ) where

import Prelude.Kore

import Test.Tasty

import Control.Applicative
    ( liftA2
    )
import Control.Exception as Exception
import Data.Default
    ( def
    )
import Data.Limit
    ( Limit (..)
    )
import qualified Data.Limit as Limit
import qualified Data.Map.Strict as Map
import Data.Set
    ( Set
    )
import qualified Data.Set as Set
import Data.Text
    ( Text
    )
import System.Exit
    ( ExitCode (..)
    )

import Kore.ASTVerifier.DefinitionVerifier
    ( verifyAndIndexDefinition
    )
import Kore.Attribute.Constructor
import Kore.Attribute.Function
import Kore.Attribute.Functional
import Kore.Attribute.Hook
import qualified Kore.Attribute.Priority as Attribute.Axiom
import qualified Kore.Attribute.Symbol as Attribute
import qualified Kore.Builtin as Builtin
import qualified Kore.Builtin.Int as Int
import qualified Kore.Error
import Kore.Exec
import Kore.IndexedModule.IndexedModule
import Kore.Internal.ApplicationSorts
import Kore.Internal.Pattern as Pattern
import Kore.Internal.Predicate
    ( makeTruePredicate_
    )
import Kore.Internal.TermLike
import qualified Kore.Internal.TermLike as TermLike
import Kore.Step
    ( Prim (..)
    , priorityAllStrategy
    , priorityAnyStrategy
    )
import Kore.Step.Rule
import Kore.Step.RulePattern
    ( RewriteRule (..)
    , RulePattern (..)
    , injectTermIntoRHS
    , rewriteRuleToTerm
    )
import Kore.Step.Search
    ( SearchType (..)
    )
import qualified Kore.Step.Search as Search
import Kore.Step.Strategy
    ( LimitExceeded (..)
    , Strategy (..)
    )
import Kore.Syntax.Definition hiding
    ( Symbol
    )
import qualified Kore.Syntax.Definition as Syntax
import qualified Kore.Verified as Verified

import Test.Kore
import qualified Test.Kore.IndexedModule.MockMetadataTools as Mock
import Test.SMT
    ( runNoSMT
    )
import Test.Tasty.HUnit.Ext

test_execPriority :: TestTree
test_execPriority = testCase "execPriority" $ actual >>= assertEqual "" expected
  where
    unlimited :: Limit Integer
    unlimited = Unlimited
    actual =
        exec
            Unlimited
            verifiedModule
            (Limit.replicate unlimited . priorityAnyStrategy)
            inputPattern
        & runNoSMT
    verifiedModule = verifiedMyModule Module
        { moduleName = ModuleName "MY-MODULE"
        , moduleSentences =
            [ asSentence mySortDecl
            , asSentence $ constructorDecl "a"
            , asSentence $ constructorDecl "b"
            , asSentence $ constructorDecl "c"
            , asSentence $ constructorDecl "d"
            , functionalAxiom "a"
            , functionalAxiom "b"
            , functionalAxiom "c"
            , functionalAxiom "d"
            , complexRewriteAxiomWithPriority "a" "b" 2
            , simpleRewriteAxiomWithPriority "a" "c" 1
            , complexRewriteAxiom "c" "d"
            ]
        , moduleAttributes = Attributes []
        }
    inputPattern = applyToNoArgs mySort "a"
    expected = applyToNoArgs mySort "d"

test_exec :: TestTree
test_exec = testCase "exec" $ actual >>= assertEqual "" expected
  where
    unlimited :: Limit Integer
    unlimited = Unlimited
    actual =
        exec
            Unlimited
            verifiedModule
            (Limit.replicate unlimited . priorityAnyStrategy)
            inputPattern
        & runNoSMT
    verifiedModule = verifiedMyModule Module
        { moduleName = ModuleName "MY-MODULE"
        , moduleSentences =
            [ asSentence mySortDecl
            , asSentence $ constructorDecl "a"
            , asSentence $ constructorDecl "b"
            , asSentence $ constructorDecl "c"
            , asSentence $ constructorDecl "d"
            , functionalAxiom "a"
            , functionalAxiom "b"
            , functionalAxiom "c"
            , functionalAxiom "d"
            , simpleRewriteAxiom "a" "b"
            , simpleRewriteAxiom "b" "c"
            , simpleRewriteAxiom "c" "d"
            ]
        , moduleAttributes = Attributes []
        }
    inputPattern = applyToNoArgs mySort "b"
    expected = applyToNoArgs mySort "d"

test_searchPriority :: [TestTree]
test_searchPriority =
    [ makeTestCase searchType | searchType <- [ ONE, STAR, PLUS, FINAL] ]
  where
    unlimited :: Limit Integer
    unlimited = Unlimited
    makeTestCase searchType =
        testCase ("searchPriority " <> show searchType) (assertion searchType)
    assertion searchType =
        actual searchType >>= assertEqual "" (expected searchType)
    actual searchType = do
        finalPattern <-
            search
                Unlimited
                verifiedModule
                (Limit.replicate unlimited . priorityAllStrategy)
                inputPattern
                searchPattern
                Search.Config { bound = Unlimited, searchType }
            & runNoSMT
        let results =
                fromMaybe
                    (error "Expected search results")
                    (extractSearchResults finalPattern)
        return results
    verifiedModule = verifiedMyModule Module
        { moduleName = ModuleName "MY-MODULE"
        , moduleSentences =
            [ asSentence mySortDecl
            , asSentence $ constructorDecl "a"
            , asSentence $ constructorDecl "b"
            , asSentence $ constructorDecl "c"
            , asSentence $ constructorDecl "d"
            , asSentence $ constructorDecl "e"
            , functionalAxiom "a"
            , functionalAxiom "b"
            , functionalAxiom "c"
            , functionalAxiom "d"
            , functionalAxiom "e"
            , complexRewriteAxiomWithPriority "a" "b" 2
            , simpleRewriteAxiomWithPriority "a" "c" 1
            , complexRewriteAxiom "c" "d"
            , complexRewriteAxiom "e" "a"
            ]
        , moduleAttributes = Attributes []
        }
    inputPattern = applyToNoArgs mySort "a"
    expected =
        let
            a = applyToNoArgs mySort "a"
            c = applyToNoArgs mySort "c"
            d = applyToNoArgs mySort "d"
        in
            \case
                ONE -> Set.fromList [c]
                STAR -> Set.fromList [a, c, d]
                PLUS -> Set.fromList [c, d]
                FINAL -> Set.fromList [d]

test_search :: [TestTree]
test_search =
    [ makeTestCase searchType | searchType <- [ ONE, STAR, PLUS, FINAL] ]
  where
    unlimited :: Limit Integer
    unlimited = Unlimited
    makeTestCase searchType =
        testCase ("search " <> show searchType) (assertion searchType)
    assertion searchType =
        actual searchType >>= assertEqual "" (expected searchType)
    actual searchType = do
        finalPattern <-
            search
                Unlimited
                verifiedModule
                (Limit.replicate unlimited . priorityAllStrategy)
                inputPattern
                searchPattern
                Search.Config { bound = Unlimited, searchType }
            & runNoSMT
        let results =
                fromMaybe
                    (error "Expected search results")
                    (extractSearchResults finalPattern)
        return results
    verifiedModule = verifiedMyModule Module
        { moduleName = ModuleName "MY-MODULE"
        , moduleSentences =
            [ asSentence mySortDecl
            , asSentence $ constructorDecl "a"
            , asSentence $ constructorDecl "b"
            , asSentence $ constructorDecl "c"
            , asSentence $ constructorDecl "d"
            , asSentence $ constructorDecl "e"
            , functionalAxiom "a"
            , functionalAxiom "b"
            , functionalAxiom "c"
            , functionalAxiom "d"
            , functionalAxiom "e"
            , simpleRewriteAxiom "a" "b"
            , simpleRewriteAxiom "a" "c"
            , simpleRewriteAxiom "c" "d"
            , simpleRewriteAxiom "e" "a"
            ]
        , moduleAttributes = Attributes []
        }
    inputPattern = applyToNoArgs mySort "a"
    expected =
        let
            a = applyToNoArgs mySort "a"
            b = applyToNoArgs mySort "b"
            c = applyToNoArgs mySort "c"
            d = applyToNoArgs mySort "d"
        in
            \case
                ONE -> Set.fromList [b, c]
                STAR -> Set.fromList [a, b, c, d]
                PLUS -> Set.fromList [b, c, d]
                FINAL -> Set.fromList [b, d]

test_searchExeedingBreadthLimit :: [TestTree]
test_searchExeedingBreadthLimit =
    [ makeTestCase searchType | searchType <- [ ONE, STAR, PLUS, FINAL] ]
  where
    unlimited :: Limit Integer
    unlimited = Unlimited
    makeTestCase searchType =
        testCase
            ("Exceed bredth limit: " <> show searchType)
            (assertion searchType)

    assertion searchType =
        shouldExeedBreadthLimit searchType `catch`
            \(_ :: LimitExceeded (Strategy (Prim Rewrite))) -> pure ()

    shouldExeedBreadthLimit :: SearchType -> IO ()
    shouldExeedBreadthLimit searchType = do
        a <- actual searchType
        when (a == expected searchType)
            $ assertFailure "Did not exceed breadth limit"

    actual searchType = do
        finalPattern <-
            search
                (Limit 0)
                verifiedModule
                (Limit.replicate unlimited . priorityAllStrategy)
                inputPattern
                searchPattern
                Search.Config { bound = Unlimited, searchType }
            & runNoSMT
        let results =
                fromMaybe
                    (error "Expected search results")
                    (extractSearchResults finalPattern)
        return results
    verifiedModule = verifiedMyModule Module
        { moduleName = ModuleName "MY-MODULE"
        , moduleSentences =
            [ asSentence mySortDecl
            , asSentence $ constructorDecl "a"
            , asSentence $ constructorDecl "b"
            , asSentence $ constructorDecl "c"
            , asSentence $ constructorDecl "d"
            , asSentence $ constructorDecl "e"
            , functionalAxiom "a"
            , functionalAxiom "b"
            , functionalAxiom "c"
            , functionalAxiom "d"
            , functionalAxiom "e"
            , simpleRewriteAxiom "a" "b"
            , simpleRewriteAxiom "a" "c"
            , simpleRewriteAxiom "c" "d"
            , simpleRewriteAxiom "e" "a"
            ]
        , moduleAttributes = Attributes []
        }
    inputPattern = applyToNoArgs mySort "a"
    expected =
        let
            a = applyToNoArgs mySort "a"
            b = applyToNoArgs mySort "b"
            c = applyToNoArgs mySort "c"
            d = applyToNoArgs mySort "d"
        in
            \case
                ONE -> Set.fromList [b, c]
                STAR -> Set.fromList [a, b, c, d]
                PLUS -> Set.fromList [b, c, d]
                FINAL -> Set.fromList [b, d]

-- | V:MySort{}
searchVar :: TermLike Variable
searchVar =
    mkElemVar $ ElementVariable Variable
        { variableName = Id "V" AstLocationTest
        , variableCounter = mempty
        , variableSort = mySort
        }

-- |
--  \and{MySort{}}(
--      V:MySort{},
--      \top{MySort{}}())
searchPattern :: Pattern Variable
searchPattern = Conditional
    { term = searchVar
    , predicate = makeTruePredicate_
    , substitution = mempty
    }

-- | Turn a disjunction of "v = ???" into Just a set of the ???. If the input is
-- not a disjunction of "v = ???", return Nothing.
extractSearchResults :: TermLike Variable -> Maybe (Set (TermLike Variable))
extractSearchResults =
    \case
        Equals_ operandSort resultSort first second
          | operandSort == mySort
            && resultSort == mySort
            && first == searchVar
          -> Just $ Set.singleton second
        Or_ sort first second
          | sort == mySort
          ->
            liftA2
                Set.union
                (extractSearchResults first)
                (extractSearchResults second)
        _ -> Nothing

verifiedMyModule
    :: Module Verified.Sentence
    -> VerifiedModule Attribute.Symbol
verifiedMyModule module_ = indexedModule
  where
    indexedModule =
        fromMaybe
            (error "Missing module: MY-MODULE")
            (Map.lookup (ModuleName "MY-MODULE") indexedModules)
    indexedModules =
        Kore.Error.assertRight
        $ verifyAndIndexDefinition Builtin.koreVerifiers definition
    definition = Definition
        { definitionAttributes = Attributes []
        , definitionModules =
            [(fmap . fmap) Builtin.externalize module_]
        }

mySortName :: Id
mySortName = Id "MySort" AstLocationTest

mySort :: Sort
mySort = SortActualSort SortActual
    { sortActualName = mySortName
    , sortActualSorts = []
    }

-- | sort MySort{} []
mySortDecl :: Verified.SentenceSort
mySortDecl = SentenceSort
    { sentenceSortName = mySortName
    , sentenceSortParameters = []
    , sentenceSortAttributes = Attributes []
    }

-- | symbol name{}() : MySort{} [functional{}(), constructor{}()]
constructorDecl :: Text -> Verified.SentenceSymbol
constructorDecl name =
    (mkSymbol_ (testId name) [] mySort)
        { sentenceSymbolAttributes = Attributes
            [ functionalAttribute
            , constructorAttribute
            ]
        }

-- |
--  axiom{R}
--      \exists{R}(
--          V:MySort{},
--          \equals{MySort{}, R}(
--              V:MySort{},
--              a{}()))
--  [functional{}()]
functionalAxiom :: Text -> Verified.Sentence
functionalAxiom name =
    SentenceAxiomSentence
        (mkAxiom
            [r]
            (mkExists v
                (mkEquals
                    (SortVariableSort r)
                    (mkElemVar v)
                    (applyToNoArgs mySort name)
                )
            )
        )
            { sentenceAxiomAttributes = Attributes [functionalAttribute] }
  where
    v = ElementVariable Variable
        { variableName = Id "V" AstLocationTest
        , variableCounter = mempty
        , variableSort = mySort
        }
    r = SortVariable $ Id "R" AstLocationTest

simpleRewriteAxiom :: Text -> Text -> Verified.Sentence
simpleRewriteAxiom lhs rhs =
    rewriteAxiomPriority lhs rhs Nothing Nothing

complexRewriteAxiom :: Text -> Text -> Verified.Sentence
complexRewriteAxiom lhs rhs =
    rewriteAxiomPriority lhs rhs Nothing (Just mkTop_)

simpleRewriteAxiomWithPriority :: Text -> Text -> Integer -> Verified.Sentence
simpleRewriteAxiomWithPriority lhs rhs priority =
    rewriteAxiomPriority lhs rhs (Just priority) Nothing

complexRewriteAxiomWithPriority :: Text -> Text -> Integer -> Verified.Sentence
complexRewriteAxiomWithPriority lhs rhs priority =
    rewriteAxiomPriority lhs rhs (Just priority) (Just mkTop_)

rewriteAxiomPriority
    :: Text
    -> Text
    -> Maybe Integer
    -> Maybe (TermLike Variable)
    -> Verified.Sentence
rewriteAxiomPriority lhsName rhsName priority antiLeft =
    ( Syntax.SentenceAxiomSentence
    . withPriority priority
    . TermLike.mkAxiom_
    )
    $ rewriteRuleToTerm
    $ RewriteRule RulePattern
        { left = applyToNoArgs mySort lhsName
        , antiLeft
        , requires = makeTruePredicate_
        , rhs = injectTermIntoRHS (applyToNoArgs mySort rhsName)
        , attributes = def
        }
  where
    withPriority =
        maybe id (axiomWithAttribute . Attribute.Axiom.priorityAttribute)

axiomWithAttribute
    :: AttributePattern
    -> SentenceAxiom (TermLike variable)
    -> SentenceAxiom (TermLike variable)
axiomWithAttribute attribute axiom =
    axiom
        { sentenceAxiomAttributes =
            currentAttributes <> Attributes [attribute]
        }
  where
    currentAttributes = sentenceAxiomAttributes axiom

applyToNoArgs :: Sort -> Text -> TermLike Variable
applyToNoArgs sort name =
    mkApplySymbol
        Symbol
            { symbolConstructor = testId name
            , symbolParams = []
            , symbolAttributes = Mock.constructorFunctionalAttributes
            , symbolSorts = applicationSorts [] sort
            }
        []

test_execGetExitCode :: TestTree
test_execGetExitCode =
    testGroup "execGetExitCode"
        [ makeTestCase "No getExitCode symbol => ExitSuccess"
              testModuleNoSymbol 42 ExitSuccess
        , makeTestCase "No getExitCode simplification axiom => ExitFailure 111"
              testModuleNoAxiom 42 $ ExitFailure 111
        , makeTestCase "Exit cell contains 0 => ExitSuccess"
              testModuleSuccessfulSimplification 0 ExitSuccess
        , makeTestCase "Exit cell contains 42 => ExitFailure 42"
              testModuleSuccessfulSimplification 42 $ ExitFailure 42
        ]
  where
    unlimited :: Limit Integer
    unlimited = Unlimited

    makeTestCase name testModule inputInteger expectedCode =
        testCase name
            $ actual testModule inputInteger >>= assertEqual "" expectedCode

    actual testModule exitCode =
        execGetExitCode
            (verifiedMyModule testModule)
            (Limit.replicate unlimited . priorityAnyStrategy)
            (Int.asInternal myIntSort exitCode)
        & runNoSMT

    -- Module with no getExitCode symbol
    testModuleNoSymbol = Module
        { moduleName = ModuleName "MY-MODULE"
        , moduleSentences = []
        , moduleAttributes = Attributes []
        }

    -- simplification of the exit code pattern will not produce an integer
    -- (no axiom present for the symbol)
    testModuleNoAxiom = Module
        { moduleName = ModuleName "MY-MODULE"
        , moduleSentences =
            [ asSentence intSortDecl
            , asSentence getExitCodeDecl
            ]
        , moduleAttributes = Attributes []
        }

    -- simplification succeeds
    testModuleSuccessfulSimplification = Module
        { moduleName = ModuleName "MY-MODULE"
        , moduleSentences =
            [ asSentence intSortDecl
            , asSentence getExitCodeDecl
            , mockGetExitCodeAxiom
            ]
        , moduleAttributes = Attributes []
        }

    myIntSortId = testId "Int"

    myIntSort = SortActualSort $ SortActual myIntSortId []

    intSortDecl :: Verified.SentenceHook
    intSortDecl = SentenceHookedSort SentenceSort
        { sentenceSortName = myIntSortId
        , sentenceSortParameters = []
        , sentenceSortAttributes = Attributes [hookAttribute Int.sort]
        }

    getExitCodeId = testId "LblgetExitCode"

    getExitCodeDecl :: Verified.SentenceSymbol
    getExitCodeDecl =
        ( mkSymbol_ getExitCodeId [myIntSort] myIntSort )
            { sentenceSymbolAttributes =
                Attributes [functionAttribute, functionalAttribute]
            }

    mockGetExitCodeAxiom =
        mkEqualityAxiom
            (mkApplySymbol getExitCodeSym [mkElemVar v]) (mkElemVar v) Nothing
      where
        v = ElementVariable Variable
            { variableName = testId "V"
            , variableCounter = mempty
            , variableSort = myIntSort
            }
        getExitCodeSym =
            Symbol
                { symbolConstructor = getExitCodeId
                , symbolParams = []
                , symbolAttributes =
                    Attribute.defaultSymbolAttributes
                    { Attribute.functional = Functional True
                    , Attribute.function = Function True
                    }
                , symbolSorts = applicationSorts [myIntSort] myIntSort
                }
