
This is the types used to define the tests as pure data. See the
Tests.lhs module for the 'interpreter'.

> module Language.SQL.SimpleSQL.TestTypes
>     (TestItem(..)
>     ,Dialect(..)) where

> import Language.SQL.SimpleSQL.Syntax

TODO: maybe make the dialect args into [dialect], then each test
checks all the dialects mentioned work, and all the dialects not
mentioned give a parse error. Not sure if this will be too awkward due
to lots of tricky exceptions/variationsx.

> data TestItem = Group String [TestItem]
>               | TestValueExpr Dialect String ValueExpr
>               | TestQueryExpr Dialect String QueryExpr
>               | TestQueryExprs Dialect String [QueryExpr]

this just checks the sql parses without error, mostly just a
intermediate when I'm too lazy to write out the parsed AST. These
should all be TODO to convert to a testqueryexpr test.

>               | ParseQueryExpr Dialect String

check that the string given fails to parse

>               | ParseQueryExprFails Dialect String
>               | ParseValueExprFails Dialect String
>                 deriving (Eq,Show)
