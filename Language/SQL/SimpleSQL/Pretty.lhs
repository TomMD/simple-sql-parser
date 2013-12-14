
This is the pretty printer code which takes AST values and turns them
back into SQL source text. It attempts to format the output nicely.

> -- | These is the pretty printing functions, which produce SQL source from ASTs. The code attempts to format the output in a readable way.
> module Language.SQL.SimpleSQL.Pretty
>     (prettyQueryExpr
>     ,prettyScalarExpr
>     ,prettyQueryExprs
>     ) where

> import Language.SQL.SimpleSQL.Syntax
> import Text.PrettyPrint
> import Data.Maybe

> -- | Convert a query expr ast to concrete syntax.
> prettyQueryExpr :: QueryExpr -> String
> prettyQueryExpr = render . queryExpr

> -- | Convert a scalar expr ast to concrete syntax.
> prettyScalarExpr :: ScalarExpr -> String
> prettyScalarExpr = render . scalarExpr

> -- | Convert a list of query exprs to concrete syntax. A semi colon is inserted following each query expr.
> prettyQueryExprs :: [QueryExpr] -> String
> prettyQueryExprs = render . vcat . map ((<> text ";\n") . queryExpr)

= scalar expressions

> scalarExpr :: ScalarExpr -> Doc
> scalarExpr (StringLit s) = quotes $ text s
> scalarExpr (NumLit s) = text s
> scalarExpr (IntervalLit v u p) =
>     text "interval" <+> quotes (text v)
>     <+> text u
>     <+> maybe empty (parens . text . show ) p
> scalarExpr (Iden i) = text i
> scalarExpr (Iden2 q i) = text q <> text "." <> text i
> scalarExpr Star = text "*"
> scalarExpr (Star2 q) = text q <> text "." <> text "*"

> scalarExpr (App f es) = text f <> parens (commaSep (map scalarExpr es))

> scalarExpr (AggregateApp f d es od) =
>     text f
>     <> parens ((case d of
>                   Just Distinct -> text "distinct"
>                   Just All -> text "all"
>                   Nothing -> empty)
>                <+> commaSep (map scalarExpr es)
>                <+> orderBy od)

> scalarExpr (WindowApp f es pb od) =
>     text f <> parens (commaSep $ map scalarExpr es)
>     <+> text "over"
>     <+> parens ((case pb of
>                     [] -> empty
>                     _ -> text "partition by"
>                           <+> nest 4 (commaSep $ map scalarExpr pb))
>                 <+> orderBy od)

> scalarExpr (SpecialOp nm [a,b,c]) | nm `elem` ["between", "not between"] =
>   scalarExpr a <+> text nm <+> scalarExpr b <+> text "and" <+> scalarExpr c

> scalarExpr (SpecialOp "extract" [a,n]) =
>   text "extract" <> parens (scalarExpr a
>                             <+> text "from"
>                             <+> scalarExpr n)

> scalarExpr (SpecialOp "substring" [a,s,e]) =
>   text "substring" <> parens (scalarExpr a
>                             <+> text "from"
>                             <+> scalarExpr s
>                             <+> text "for"
>                             <+> scalarExpr e)

> scalarExpr (SpecialOp nm es) =
>   text nm <+> parens (commaSep $ map scalarExpr es)

> scalarExpr (PrefixOp f e) = text f <+> scalarExpr e
> scalarExpr (PostfixOp f e) = scalarExpr e <+> text f
> scalarExpr (BinOp e0 "and" e1) =
>     sep [scalarExpr e0, text "and" <+> scalarExpr e1]
> scalarExpr (BinOp e0 f e1) =
>     scalarExpr e0 <+> text f <+> scalarExpr e1

> scalarExpr (Case t ws els) =
>     sep [text "case" <+> maybe empty scalarExpr t
>         ,nest 4 (sep (map w ws
>                       ++ maybeToList (fmap e els)))
>         ,text "end"]
>   where
>     w (t0,t1) = sep [text "when" <+> scalarExpr t0
>                     ,text "then" <+> scalarExpr t1]
>     e el = text "else" <+> scalarExpr el
> scalarExpr (Parens e) = parens $ scalarExpr e
> scalarExpr (Cast e (TypeName tn)) =
>     text "cast" <> parens (sep [scalarExpr e
>                                ,text "as"
>                                ,text tn])

> scalarExpr (CastOp (TypeName tn) s) =
>     text tn <+> quotes (text s)

> scalarExpr (SubQueryExpr ty qe) =
>     (case ty of
>         SqSq -> empty
>         SqExists -> text "exists"
>         SqAll -> text "all"
>         SqSome -> text "some"
>         SqAny -> text "any"
>     ) <+> parens (queryExpr qe)

> scalarExpr (In b se x) =
>     sep [scalarExpr se
>         ,if b then empty else text "not"
>         ,text "in"
>         ,parens (nest 4 $
>                  case x of
>                      InList es -> commaSep $ map scalarExpr es
>                      InQueryExpr qe -> queryExpr qe)]

= query expressions

> queryExpr :: QueryExpr -> Doc
> queryExpr (Select d sl fr wh gb hv od lm off) =
>   sep [text "select"
>       ,case d of
>           All -> empty
>           Distinct -> text "distinct"
>       ,nest 4 $ sep [selectList sl]
>       ,from fr
>       ,maybeScalarExpr "where" wh
>       ,grpBy gb
>       ,maybeScalarExpr "having" hv
>       ,orderBy od
>       ,maybeScalarExpr "limit" lm
>       ,maybeScalarExpr "offset" off
>       ]
> queryExpr (CombineQueryExpr q1 ct d c q2) =
>   sep [queryExpr q1
>       ,text (case ct of
>                 Union -> "union"
>                 Intersect -> "intersect"
>                 Except -> "except")
>        <+> case d of
>                All -> empty
>                Distinct -> text "distinct"
>        <+> case c of
>                Corresponding -> text "corresponding"
>                Respectively -> empty
>       ,queryExpr q2]
> queryExpr (With withs qe) =
>   text "with"
>   <+> vcat [nest 4
>             (vcat $ punctuate comma $ flip map withs $ \(n,q) ->
>              text n <+> text "as" <+> parens (queryExpr q))
>            ,queryExpr qe]

> selectList :: [(Maybe String, ScalarExpr)] -> Doc
> selectList is = commaSep $ map si is
>   where
>     si (al,e) = scalarExpr e <+> maybe empty alias al
>     alias al = text "as" <+> text al

> from :: [TableRef] -> Doc
> from [] = empty
> from ts =
>     sep [text "from"
>         ,nest 4 $ commaSep $ map tr ts]
>   where
>     tr (TRSimple t) = text t
>     tr (TRAlias t a cs) =
>         tr t <+> text "as" <+> text a
>         <+> maybe empty (parens . commaSep . map text) cs
>     tr (TRParens t) = parens $ tr t
>     tr (TRQueryExpr q) = parens $ queryExpr q
>     tr (TRJoin t0 jt t1 jc) =
>        sep [tr t0
>            ,joinText jt jc
>            ,tr t1
>            ,joinCond jc]
>     joinText jt jc =
>       sep [case jc of
>               Just JoinNatural -> text "natural"
>               _ -> empty
>           ,case jt of
>               JInner -> text "inner"
>               JLeft -> text "left"
>               JRight -> text "right"
>               JFull -> text "full"
>               JCross -> text "cross"
>           ,text "join"]
>     joinCond (Just (JoinOn e)) = text "on" <+> scalarExpr e
>     joinCond (Just (JoinUsing es)) = text "using" <+> parens (commaSep $ map text es)
>     joinCond Nothing = empty
>     joinCond (Just JoinNatural) = empty

> maybeScalarExpr :: String -> Maybe ScalarExpr -> Doc
> maybeScalarExpr k = maybe empty
>       (\e -> sep [text k
>                  ,nest 4 $ scalarExpr e])

> grpBy :: [ScalarExpr] -> Doc
> grpBy [] = empty
> grpBy gs = sep [text "group by"
>                ,nest 4 $ commaSep $ map scalarExpr gs]

> orderBy :: [(ScalarExpr,Direction)] -> Doc
> orderBy [] = empty
> orderBy os = sep [text "order by"
>                  ,nest 4 $ commaSep $ map f os]
>   where
>     f (e,Asc) = scalarExpr e
>     f (e,Desc) = scalarExpr e <+> text "desc"


= utils

> commaSep :: [Doc] -> Doc
> commaSep ds = sep $ punctuate comma ds
