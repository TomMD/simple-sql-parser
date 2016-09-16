
> -- | The AST for SQL queries.
> {-# LANGUAGE DeriveDataTypeable #-}
> {-# LANGUAGE DeriveGeneric #-}
> module Language.SQL.SimpleSQL.Syntax
>     (-- * Value expressions
>      ValueExpr(..)
>     ,Name(..)
>     ,TypeName(..)
>     ,IntervalTypeField(..)
>     ,PrecMultiplier(..)
>     ,PrecUnits(..)
>     ,SetQuantifier(..)
>     ,SortSpec(..)
>     ,Direction(..)
>     ,NullsOrder(..)
>     ,InPredValue(..)
>     ,SubQueryExprType(..)
>     ,CompPredQuantifier(..)
>     ,Frame(..)
>     ,FrameRows(..)
>     ,FramePos(..)
>      -- * Query expressions
>     ,QueryExpr(..)
>     ,makeSelect
>     ,CombineOp(..)
>     ,Corresponding(..)
>     ,Alias(..)
>     ,GroupingExpr(..)
>      -- ** From
>     ,TableRef(..)
>     ,JoinType(..)
>     ,JoinCondition(..)
>      -- * dialect
>     ,Dialect(..)
>      -- * comment
>     ,Comment(..)
>     ) where

> import Data.Data
> import GHC.Generics (Generic)
> import Control.DeepSeq (NFData)

> -- | Represents a value expression. This is used for the expressions
> -- in select lists. It is also used for expressions in where, group
> -- by, having, order by and so on.
> data ValueExpr
>     = -- | a numeric literal optional decimal point, e+-
>       -- integral exponent, e.g
>       --
>       -- * 10
>       --
>       -- * 10.
>       --
>       -- * .1
>       --
>       -- * 10.1
>       --
>       -- * 1e5
>       --
>       -- * 12.34e-6
>       NumLit String
>       -- | string literal, currently only basic strings between
>       -- single quotes with a single quote escaped using ''
>     | StringLit String
>       -- | text of interval literal, units of interval precision,
>       -- e.g. interval 3 days (3)
>     | IntervalLit
>       {ilSign :: Maybe Bool -- ^ true if + used, false if - used
>       ,ilLiteral :: String -- ^ literal text
>       ,ilFrom :: IntervalTypeField
>       ,ilTo :: Maybe IntervalTypeField
>       }
>       -- | identifier with parts separated by dots
>     | Iden [Name]
>       -- | star, as in select *, t.*, count(*)
>     | Star
>       -- | function application (anything that looks like c style
>       -- function application syntactically)
>     | App [Name] [ValueExpr]
>       -- | aggregate application, which adds distinct or all, and
>       -- order by, to regular function application
>     | AggregateApp
>       {aggName :: [Name] -- ^ aggregate function name
>       ,aggDistinct :: SetQuantifier -- ^ distinct
>       ,aggArgs :: [ValueExpr]-- ^ args
>       ,aggOrderBy :: [SortSpec] -- ^ order by
>       ,aggFilter :: Maybe ValueExpr -- ^ filter
>       }
>       -- | aggregates with within group
>     | AggregateAppGroup
>       {aggName :: [Name] -- ^ aggregate function name
>       ,aggArgs :: [ValueExpr] -- ^ args
>       ,aggGroup :: [SortSpec] -- ^ within group
>       }
>       -- | window application, which adds over (partition by a order
>       -- by b) to regular function application. Explicit frames are
>       -- not currently supported
>     | WindowApp
>       {wnName :: [Name] -- ^ window function name
>       ,wnArgs :: [ValueExpr] -- ^ args
>       ,wnPartition :: [ValueExpr] -- ^ partition by
>       ,wnOrderBy :: [SortSpec] -- ^ order by
>       ,wnFrame :: Maybe Frame -- ^ frame clause
>       }
>       -- | Infix binary operators. This is used for symbol operators
>       -- (a + b), keyword operators (a and b) and multiple keyword
>       -- operators (a is similar to b)
>     | BinOp ValueExpr [Name] ValueExpr
>       -- | Prefix unary operators. This is used for symbol
>       -- operators, keyword operators and multiple keyword operators.
>     | PrefixOp [Name] ValueExpr
>       -- | Postfix unary operators. This is used for symbol
>       -- operators, keyword operators and multiple keyword operators.
>     | PostfixOp [Name] ValueExpr
>       -- | Used for ternary, mixfix and other non orthodox
>       -- operators. Currently used for row constructors, and for
>       -- between.
>     | SpecialOp [Name] [ValueExpr]
>       -- | Used for the operators which look like functions
>       -- except the arguments are separated by keywords instead
>       -- of commas. The maybe is for the first unnamed argument
>       -- if it is present, and the list is for the keyword argument
>       -- pairs.
>     | SpecialOpK [Name] (Maybe ValueExpr) [(String,ValueExpr)]
>       -- | case expression. both flavours supported
>     | Case
>       {caseTest :: Maybe ValueExpr -- ^ test value
>       ,caseWhens :: [([ValueExpr],ValueExpr)] -- ^ when branches
>       ,caseElse :: Maybe ValueExpr -- ^ else value
>       }
>     | Parens ValueExpr
>       -- | cast(a as typename)
>     | Cast ValueExpr TypeName
>       -- | prefix 'typed literal', e.g. int '42'
>     | TypedLit TypeName String
>       -- | exists, all, any, some subqueries
>     | SubQueryExpr SubQueryExprType QueryExpr
>       -- | in list literal and in subquery, if the bool is false it
>       -- means not in was used ('a not in (1,2)')
>     | In Bool ValueExpr InPredValue
>     | Parameter -- ^ Represents a ? in a parameterized query
>     | HostParameter String (Maybe String) -- ^ represents a host
>                                           -- parameter, e.g. :a. The
>                                           -- Maybe String is for the
>                                           -- indicator, e.g. :var
>                                           -- indicator :nl
>     | QuantifiedComparison
>             ValueExpr
>             [Name] -- operator
>             CompPredQuantifier
>             QueryExpr
>     | Match ValueExpr Bool -- true if unique
>           QueryExpr
>     | Array ValueExpr [ValueExpr] -- ^ represents an array
>                                   -- access expression, or an array ctor
>                                   -- e.g. a[3]. The first
>                                   -- valueExpr is the array, the
>                                   -- second is the subscripts/ctor args
>     | ArrayCtor QueryExpr -- ^ this is used for the query expression version of array constructors, e.g. array(select * from t)
>     | CSStringLit String String
>     | Escape ValueExpr Char
>     | UEscape ValueExpr Char
>     | Collate ValueExpr [Name]
>     | MultisetBinOp ValueExpr CombineOp SetQuantifier ValueExpr
>     | MultisetCtor [ValueExpr]
>     | MultisetQueryCtor QueryExpr
>     | NextValueFor [Name]
>     | VEComment [Comment] ValueExpr
>       deriving (Eq,Show,Read,Data,Typeable,Generic)

> -- | Represents an identifier name, which can be quoted or unquoted.
> data Name = Name String
>           | QName String
>           | UQName String
>           | DQName String String String
>             -- ^ dialect quoted name, the fields are start quote, end quote and the string itself, e.g. `something` is parsed to DQName "`" "`" "something, and $a$ test $a$ is parsed to DQName "$a$" "$a" " test "
>             deriving (Eq,Show,Read,Data,Typeable,Generic)

> -- | Represents a type name, used in casts.
> data TypeName
>     = TypeName [Name]
>     | PrecTypeName [Name] Integer
>     | PrecScaleTypeName [Name] Integer Integer
>     | PrecLengthTypeName [Name] Integer (Maybe PrecMultiplier) (Maybe PrecUnits)
>       -- precision, characterset, collate
>     | CharTypeName [Name] (Maybe Integer) [Name] [Name]
>     | TimeTypeName [Name] (Maybe Integer) Bool -- true == with time zone
>     | RowTypeName [(Name,TypeName)]
>     | IntervalTypeName IntervalTypeField (Maybe IntervalTypeField)
>     | ArrayTypeName TypeName (Maybe Integer)
>     | MultisetTypeName TypeName
>       deriving (Eq,Show,Read,Data,Typeable,Generic)

> data IntervalTypeField = Itf String (Maybe (Integer, Maybe Integer))
>                          deriving (Eq,Show,Read,Data,Typeable,Generic)

> data PrecMultiplier = PrecK | PrecM | PrecG | PrecT | PrecP
>                       deriving (Eq,Show,Read,Data,Typeable,Generic)
> data PrecUnits = PrecCharacters
>                | PrecOctets
>                 deriving (Eq,Show,Read,Data,Typeable,Generic)

> -- | Used for 'expr in (value expression list)', and 'expr in
> -- (subquery)' syntax.
> data InPredValue = InList [ValueExpr]
>                  | InQueryExpr QueryExpr
>                    deriving (Eq,Show,Read,Data,Typeable,Generic)

not sure if scalar subquery, exists and unique should be represented like this

> -- | A subquery in a value expression.
> data SubQueryExprType
>     = -- | exists (query expr)
>       SqExists
>       -- | unique (query expr)
>     | SqUnique
>       -- | a scalar subquery
>     | SqSq
>       deriving (Eq,Show,Read,Data,Typeable,Generic)

> data CompPredQuantifier
>     = CPAny
>     | CPSome
>     | CPAll
>       deriving (Eq,Show,Read,Data,Typeable,Generic)

> -- | Represents one field in an order by list.
> data SortSpec = SortSpec ValueExpr Direction NullsOrder
>                 deriving (Eq,Show,Read,Data,Typeable,Generic)

> -- | Represents 'nulls first' or 'nulls last' in an order by clause.
> data NullsOrder = NullsOrderDefault
>                 | NullsFirst
>                 | NullsLast
>                   deriving (Eq,Show,Read,Data,Typeable,Generic)

> -- | Represents the frame clause of a window
> -- this can be [range | rows] frame_start
> -- or [range | rows] between frame_start and frame_end
> data Frame = FrameFrom FrameRows FramePos
>            | FrameBetween FrameRows FramePos FramePos
>              deriving (Eq,Show,Read,Data,Typeable,Generic)

> -- | Represents whether a window frame clause is over rows or ranges.
> data FrameRows = FrameRows | FrameRange
>                  deriving (Eq,Show,Read,Data,Typeable,Generic)

> -- | represents the start or end of a frame
> data FramePos = UnboundedPreceding
>               | Preceding ValueExpr
>               | Current
>               | Following ValueExpr
>               | UnboundedFollowing
>                 deriving (Eq,Show,Read,Data,Typeable,Generic)

> -- | Represents a query expression, which can be:
> --
> -- * a regular select;
> --
> -- * a set operator (union, except, intersect);
> --
> -- * a common table expression (with);
> --
> -- * a table value constructor (values (1,2),(3,4)); or
> --
> -- * an explicit table (table t).
> data QueryExpr
>     = Select
>       {qeSetQuantifier :: SetQuantifier
>       ,qeSelectList :: [(ValueExpr,Maybe Name)]
>        -- ^ the expressions and the column aliases

TODO: consider breaking this up. The SQL grammar has
queryexpr = select <select list> [<table expression>]
table expression = <from> [where] [groupby] [having] ...

This would make some things a bit cleaner?

>       ,qeFrom :: [TableRef]
>       ,qeWhere :: Maybe ValueExpr
>       ,qeGroupBy :: [GroupingExpr]
>       ,qeHaving :: Maybe ValueExpr
>       ,qeOrderBy :: [SortSpec]
>       ,qeOffset :: Maybe ValueExpr
>       ,qeFetchFirst :: Maybe ValueExpr
>       }
>     | CombineQueryExpr
>       {qe0 :: QueryExpr
>       ,qeCombOp :: CombineOp
>       ,qeSetQuantifier :: SetQuantifier
>       ,qeCorresponding :: Corresponding
>       ,qe1 :: QueryExpr
>       }
>     | With
>       {qeWithRecursive :: Bool
>       ,qeViews :: [(Alias,QueryExpr)]
>       ,qeQueryExpression :: QueryExpr}
>     | Values [[ValueExpr]]
>     | Table [Name]
>     | QEComment [Comment] QueryExpr
>       deriving (Eq,Show,Read,Data,Typeable,Generic)

TODO: add queryexpr parens to deal with e.g.
(select 1 union select 2) union select 3
I'm not sure if this is valid syntax or not.

> -- | Helper/'default' value for query exprs to make creating query
> -- expr values a little easier. It is defined like this:
> --
> -- > makeSelect :: QueryExpr
> -- > makeSelect = Select {qeSetQuantifier = SQDefault
> -- >                     ,qeSelectList = []
> -- >                     ,qeFrom = []
> -- >                     ,qeWhere = Nothing
> -- >                     ,qeGroupBy = []
> -- >                     ,qeHaving = Nothing
> -- >                     ,qeOrderBy = []
> -- >                     ,qeOffset = Nothing
> -- >                     ,qeFetchFirst = Nothing}

> makeSelect :: QueryExpr
> makeSelect = Select {qeSetQuantifier = SQDefault
>                     ,qeSelectList = []
>                     ,qeFrom = []
>                     ,qeWhere = Nothing
>                     ,qeGroupBy = []
>                     ,qeHaving = Nothing
>                     ,qeOrderBy = []
>                     ,qeOffset = Nothing
>                     ,qeFetchFirst = Nothing}

> -- | Represents the Distinct or All keywords, which can be used
> -- before a select list, in an aggregate/window function
> -- application, or in a query expression set operator.
> data SetQuantifier = SQDefault | Distinct | All deriving (Eq,Show,Read,Data,Typeable,Generic)

> -- | The direction for a column in order by.
> data Direction = DirDefault | Asc | Desc deriving (Eq,Show,Read,Data,Typeable,Generic)
> -- | Query expression set operators.
> data CombineOp = Union | Except | Intersect deriving (Eq,Show,Read,Data,Typeable,Generic)
> -- | Corresponding, an option for the set operators.
> data Corresponding = Corresponding | Respectively deriving (Eq,Show,Read,Data,Typeable,Generic)

> -- | Represents an item in a group by clause.
> data GroupingExpr
>     = GroupingParens [GroupingExpr]
>     | Cube [GroupingExpr]
>     | Rollup [GroupingExpr]
>     | GroupingSets [GroupingExpr]
>     | SimpleGroup ValueExpr
>       deriving (Eq,Show,Read,Data,Typeable,Generic)

> -- | Represents a entry in the csv of tables in the from clause.
> data TableRef = -- | from t / from s.t
>                 TRSimple [Name]
>                 -- | from a join b, the bool is true if natural was used
>               | TRJoin TableRef Bool JoinType TableRef (Maybe JoinCondition)
>                 -- | from (a)
>               | TRParens TableRef
>                 -- | from a as b(c,d)
>               | TRAlias TableRef Alias
>                 -- | from (query expr)
>               | TRQueryExpr QueryExpr
>                 -- | from function(args)
>               | TRFunction [Name] [ValueExpr]
>                 -- | from lateral t
>               | TRLateral TableRef
>                 deriving (Eq,Show,Read,Data,Typeable,Generic)

> -- | Represents an alias for a table valued expression, used in with
> -- queries and in from alias, e.g. select a from t u, select a from t u(b),
> -- with a(c) as select 1, select * from a.
> data Alias = Alias Name (Maybe [Name])
>              deriving (Eq,Show,Read,Data,Typeable,Generic)

> -- | The type of a join.
> data JoinType = JInner | JLeft | JRight | JFull | JCross
>                 deriving (Eq,Show,Read,Data,Typeable,Generic)

> -- | The join condition.
> data JoinCondition = JoinOn ValueExpr -- ^ on expr
>                    | JoinUsing [Name] -- ^ using (column list)
>                      deriving (Eq,Show,Read,Data,Typeable,Generic)


> -- | Used to set the dialect used for parsing and pretty printing,
> -- very unfinished at the moment.
> data Dialect = SQL2011
>              | MySQL
>                deriving (Eq,Show,Read,Data,Typeable,Generic)


> -- | Comment. Useful when generating SQL code programmatically.
> data Comment = BlockComment String
>                deriving (Eq,Show,Read,Data,Typeable,Generic)

> -- NFData instances
> instance NFData Alias
> instance NFData Comment
> instance NFData CombineOp
> instance NFData CompPredQuantifier
> instance NFData Corresponding
> instance NFData Direction
> instance NFData Frame
> instance NFData FramePos
> instance NFData FrameRows
> instance NFData GroupingExpr
> instance NFData InPredValue
> instance NFData IntervalTypeField
> instance NFData JoinCondition
> instance NFData JoinType
> instance NFData Name
> instance NFData NullsOrder
> instance NFData PrecMultiplier
> instance NFData PrecUnits
> instance NFData QueryExpr
> instance NFData SetQuantifier
> instance NFData SortSpec
> instance NFData SubQueryExprType
> instance NFData TableRef
> instance NFData TypeName
> instance NFData ValueExpr
