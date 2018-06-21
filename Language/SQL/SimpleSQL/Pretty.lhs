
> -- | These is the pretty printing functions, which produce SQL
> -- source from ASTs. The code attempts to format the output in a
> -- readable way.
> module Language.SQL.SimpleSQL.Pretty
>     (prettyQueryExpr
>     ,prettyValueExpr
>     ,prettyQueryExprs
>     ) where

TODO: there should be more comments in this file, especially the bits
which have been changed to try to improve the layout of the output.

> import Prelude hiding ((<>))
>
> import Language.SQL.SimpleSQL.Syntax
> import Text.PrettyPrint (render, vcat, text, (<>), (<+>), empty, parens,
>                          nest, Doc, punctuate, comma, sep, quotes,
>                          doubleQuotes, brackets,hcat)
> import Data.Maybe (maybeToList, catMaybes)
> import Data.List (intercalate)

> -- | Convert a query expr ast to concrete syntax.
> prettyQueryExpr :: Dialect -> QueryExpr -> String
> prettyQueryExpr d = render . queryExpr d

> -- | Convert a value expr ast to concrete syntax.
> prettyValueExpr :: Dialect -> ValueExpr -> String
> prettyValueExpr d = render . valueExpr d

> -- | Convert a list of query exprs to concrete syntax. A semi colon
> -- is inserted after each query expr.
> prettyQueryExprs :: Dialect -> [QueryExpr] -> String
> prettyQueryExprs d = render . vcat . map ((<> text ";\n") . queryExpr d)

= value expressions

> valueExpr :: Dialect -> ValueExpr -> Doc
> valueExpr _ (StringLit s) = quotes $ text $ doubleUpQuotes s

> valueExpr _ (NumLit s) = text s
> valueExpr _ (IntervalLit s v f t) =
>     text "interval"
>     <+> me (\x -> if x then text "+" else text "-") s
>     <+> quotes (text v)
>     <+> intervalTypeField f
>     <+> me (\x -> text "to" <+> intervalTypeField x) t
> valueExpr _ (Iden i) = names i
> valueExpr _ Star = text "*"
> valueExpr _ Parameter = text "?"
> valueExpr _ (HostParameter p i) =
>     text (':':p)
>     <+> me (\i' -> text "indicator" <+> text (':':i')) i

> valueExpr d (App f es) = names f <> parens (commaSep (map (valueExpr d) es))

> valueExpr dia (AggregateApp f d es od fil) =
>     names f
>     <> parens ((case d of
>                   Distinct -> text "distinct"
>                   All -> text "all"
>                   SQDefault -> empty)
>                <+> commaSep (map (valueExpr dia) es)
>                <+> orderBy dia od)
>     <+> me (\x -> text "filter"
>                   <+> parens (text "where" <+> valueExpr dia x)) fil

> valueExpr d (AggregateAppGroup f es od) =
>     names f
>     <> parens (commaSep (map (valueExpr d) es))
>     <+> if null od
>         then empty
>         else text "within group" <+> parens (orderBy d od)

> valueExpr d (WindowApp f es pb od fr) =
>     names f <> parens (commaSep $ map (valueExpr d) es)
>     <+> text "over"
>     <+> parens ((case pb of
>                     [] -> empty
>                     _ -> text "partition by"
>                           <+> nest 13 (commaSep $ map (valueExpr d) pb))
>                 <+> orderBy d od
>     <+> me frd fr)
>   where
>     frd (FrameFrom rs fp) = rsd rs <+> fpd fp
>     frd (FrameBetween rs fps fpe) =
>         rsd rs <+> text "between" <+> fpd fps
>         <+> text "and" <+> fpd fpe
>     rsd rs = case rs of
>                  FrameRows -> text "rows"
>                  FrameRange -> text "range"
>     fpd UnboundedPreceding = text "unbounded preceding"
>     fpd UnboundedFollowing = text "unbounded following"
>     fpd Current = text "current row"
>     fpd (Preceding e) = valueExpr d e <+> text "preceding"
>     fpd (Following e) = valueExpr d e <+> text "following"

> valueExpr dia (SpecialOp nm [a,b,c]) | nm `elem` [[Name "between"]
>                                                  ,[Name "not between"]] =
>   sep [valueExpr dia a
>       ,names nm <+> valueExpr dia b
>       ,nest (length (unnames nm) + 1) $ text "and" <+> valueExpr dia c]

> valueExpr d (SpecialOp [Name "rowctor"] as) =
>     parens $ commaSep $ map (valueExpr d) as

> valueExpr d (SpecialOp nm es) =
>   names nm <+> parens (commaSep $ map (valueExpr d) es)

> valueExpr d (SpecialOpK nm fs as) =
>     names nm <> parens (sep $ catMaybes
>         (fmap (valueExpr d) fs
>          : map (\(n,e) -> Just (text n <+> valueExpr d e)) as))

> valueExpr d (PrefixOp f e) = names f <+> valueExpr d e
> valueExpr d (PostfixOp f e) = valueExpr d e <+> names f
> valueExpr d e@(BinOp _ op _) | op `elem` [[Name "and"], [Name "or"]] =
>     -- special case for and, or, get all the ands so we can vcat them
>     -- nicely
>     case ands e of
>       (e':es) -> vcat (valueExpr d e'
>                        : map ((names op <+>) . valueExpr d) es)
>       [] -> empty -- shouldn't be possible
>   where
>     ands (BinOp a op' b) | op == op' = ands a ++ ands b
>     ands x = [x]
> -- special case for . we don't use whitespace
> valueExpr d (BinOp e0 [Name "."] e1) =
>     valueExpr d e0 <> text "." <> valueExpr d e1
> valueExpr d (BinOp e0 f e1) =
>     valueExpr d e0 <+> names f <+> valueExpr d e1

> valueExpr dia (Case t ws els) =
>     sep $ [text "case" <+> me (valueExpr dia) t]
>           ++ map w ws
>           ++ maybeToList (fmap e els)
>           ++ [text "end"]
>   where
>     w (t0,t1) =
>       text "when" <+> nest 5 (commaSep $ map (valueExpr dia) t0)
>       <+> text "then" <+> nest 5 (valueExpr dia t1)
>     e el = text "else" <+> nest 5 (valueExpr dia el)
> valueExpr d (Parens e) = parens $ valueExpr d e
> valueExpr d (Cast e tn) =
>     text "cast" <> parens (sep [valueExpr d e
>                                ,text "as"
>                                ,typeName tn])

> valueExpr _ (TypedLit tn s) =
>     typeName tn <+> quotes (text s)

> valueExpr d (SubQueryExpr ty qe) =
>     (case ty of
>         SqSq -> empty
>         SqExists -> text "exists"
>         SqUnique -> text "unique"
>     ) <+> parens (queryExpr d qe)

> valueExpr d (QuantifiedComparison v c cp sq) =
>     valueExpr d v
>     <+> names c
>     <+> (text $ case cp of
>              CPAny -> "any"
>              CPSome -> "some"
>              CPAll -> "all")
>     <+> parens (queryExpr d sq)

> valueExpr d (Match v u sq) =
>     valueExpr d v
>     <+> text "match"
>     <+> (if u then text "unique" else empty)
>     <+> parens (queryExpr d sq)

> valueExpr d (In b se x) =
>     valueExpr d se <+>
>     (if b then empty else text "not")
>     <+> text "in"
>     <+> parens (nest (if b then 3 else 7) $
>                  case x of
>                      InList es -> commaSep $ map (valueExpr d) es
>                      InQueryExpr qe -> queryExpr d qe)

> valueExpr d (Array v es) =
>     valueExpr d v <> brackets (commaSep $ map (valueExpr d) es)

> valueExpr d (ArrayCtor q) =
>     text "array" <> parens (queryExpr d q)

> valueExpr d (MultisetCtor es) =
>     text "multiset" <> brackets (commaSep $ map (valueExpr d) es)

> valueExpr d (MultisetQueryCtor q) =
>     text "multiset" <> parens (queryExpr d q)

> valueExpr d (MultisetBinOp a c q b) =
>     sep
>     [valueExpr d a
>     ,text "multiset"
>     ,text $ case c of
>                 Union -> "union"
>                 Intersect -> "intersect"
>                 Except -> "except"
>     ,case q of
>          SQDefault -> empty
>          All -> text "all"
>          Distinct -> text "distinct"
>     ,valueExpr d b]



> valueExpr _ (CSStringLit cs st) =
>   text cs <> quotes (text $ doubleUpQuotes st)

> valueExpr d (Escape v e) =
>     valueExpr d v <+> text "escape" <+> text [e]

> valueExpr d (UEscape v e) =
>     valueExpr d v <+> text "uescape" <+> text [e]

> valueExpr d (Collate v c) =
>     valueExpr d v <+> text "collate" <+> names c

> valueExpr _ (NextValueFor ns) =
>     text "next value for" <+> names ns

> valueExpr d (VEComment cmt v) =
>     vcat $ map comment cmt ++ [valueExpr d v]

> doubleUpQuotes :: String -> String
> doubleUpQuotes [] = []
> doubleUpQuotes ('\'':cs) = '\'':'\'':doubleUpQuotes cs
> doubleUpQuotes (c:cs) = c:doubleUpQuotes cs

> doubleUpDoubleQuotes :: String -> String
> doubleUpDoubleQuotes [] = []
> doubleUpDoubleQuotes ('"':cs) = '"':'"':doubleUpDoubleQuotes cs
> doubleUpDoubleQuotes (c:cs) = c:doubleUpDoubleQuotes cs



> unname :: Name -> String
> unname (QName n) = "\"" ++ doubleUpDoubleQuotes n ++ "\""
> unname (UQName n) = "U&\"" ++ doubleUpDoubleQuotes n ++ "\""
> unname (Name n) = n
> unname (DQName s e n) = s ++ n ++ e

> unnames :: [Name] -> String
> unnames ns = intercalate "." $ map unname ns


> name :: Name -> Doc
> name (QName n) = doubleQuotes $ text $ doubleUpDoubleQuotes n
> name (UQName n) =
>     text "U&" <> doubleQuotes (text $ doubleUpDoubleQuotes n)
> name (Name n) = text n
> name (DQName s e n) = text s <> text n <> text e

> names :: [Name] -> Doc
> names ns = hcat $ punctuate (text ".") $ map name ns

> typeName :: TypeName -> Doc
> typeName (TypeName t) = names t
> typeName (PrecTypeName t a) = names t <+> parens (text $ show a)
> typeName (PrecScaleTypeName t a b) =
>     names t <+> parens (text (show a) <+> comma <+> text (show b))
> typeName (PrecLengthTypeName t i m u) =
>     names t
>     <> parens (text (show i)
>                <> me (\x -> case x of
>                            PrecK -> text "K"
>                            PrecM -> text "M"
>                            PrecG -> text "G"
>                            PrecT -> text "T"
>                            PrecP -> text "P") m
>                <+> me (\x -> case x of
>                        PrecCharacters -> text "CHARACTERS"
>                        PrecOctets -> text "OCTETS") u)
> typeName (CharTypeName t i cs col) =
>     names t
>     <> me (\x -> parens (text $ show x)) i
>     <+> (if null cs
>          then empty
>          else text "character set" <+> names cs)
>     <+> (if null col
>          then empty
>          else text "collate" <+> names col)
> typeName (TimeTypeName t i tz) =
>     names t
>     <> me (\x -> parens (text $ show x)) i
>     <+> text (if tz
>               then "with time zone"
>               else "without time zone")
> typeName (RowTypeName cs) =
>     text "row" <> parens (commaSep $ map f cs)
>   where
>     f (n,t) = name n <+> typeName t
> typeName (IntervalTypeName f t) =
>     text "interval"
>     <+> intervalTypeField f
>     <+> me (\x -> text "to" <+> intervalTypeField x) t

> typeName (ArrayTypeName tn sz) =
>     typeName tn <+> text "array" <+> me (brackets . text . show) sz

> typeName (MultisetTypeName tn) =
>     typeName tn <+> text "multiset"

> intervalTypeField :: IntervalTypeField -> Doc
> intervalTypeField (Itf n p) =
>     text n
>     <+> me (\(x,x1) ->
>              parens (text (show x)
>                      <+> me (\y -> (sep [comma,text (show y)])) x1)) p


= query expressions

> queryExpr :: Dialect -> QueryExpr -> Doc
> queryExpr dia (Select d sl fr wh gb hv od off fe) =
>   sep [text "select"
>       ,case d of
>           SQDefault -> empty
>           All -> text "all"
>           Distinct -> text "distinct"
>       ,nest 7 $ sep [selectList dia sl]
>       ,from dia fr
>       ,maybeValueExpr dia "where" wh
>       ,grpBy dia gb
>       ,maybeValueExpr dia "having" hv
>       ,orderBy dia od
>       ,me (\e -> text "offset" <+> valueExpr dia e <+> text "rows") off
>       ,fetchFirst
>       ]
>   where
>     fetchFirst =
>       me (\e -> if dia == MySQL
>                 then text "limit" <+> valueExpr dia e
>                 else text "fetch first" <+> valueExpr dia e
>                      <+> text "rows only") fe

> queryExpr dia (CombineQueryExpr q1 ct d c q2) =
>   sep [queryExpr dia q1
>       ,text (case ct of
>                 Union -> "union"
>                 Intersect -> "intersect"
>                 Except -> "except")
>        <+> case d of
>                SQDefault -> empty
>                All -> text "all"
>                Distinct -> text "distinct"
>        <+> case c of
>                Corresponding -> text "corresponding"
>                Respectively -> empty
>       ,queryExpr dia q2]
> queryExpr d (With rc withs qe) =
>   text "with" <+> (if rc then text "recursive" else empty)
>   <+> vcat [nest 5
>             (vcat $ punctuate comma $ flip map withs $ \(n,q) ->
>              alias n <+> text "as" <+> parens (queryExpr d q))
>            ,queryExpr d qe]
> queryExpr d (Values vs) =
>     text "values"
>     <+> nest 7 (commaSep (map (parens . commaSep . map (valueExpr d)) vs))
> queryExpr _ (Table t) = text "table" <+> names t
> queryExpr d (QEComment cmt v) =
>     vcat $ map comment cmt ++ [queryExpr d v]


> alias :: Alias -> Doc
> alias (Alias nm cols) =
>     text "as" <+> name nm
>     <+> me (parens . commaSep . map name) cols

> selectList :: Dialect -> [(ValueExpr,Maybe Name)] -> Doc
> selectList d is = commaSep $ map si is
>   where
>     si (e,al) = valueExpr d e <+> me als al
>     als al = text "as" <+> name al

> from :: Dialect -> [TableRef] -> Doc
> from _ [] = empty
> from d ts =
>     sep [text "from"
>         ,nest 5 $ vcat $ punctuate comma $ map tr ts]
>   where
>     tr (TRSimple t) = names t
>     tr (TRLateral t) = text "lateral" <+> tr t
>     tr (TRFunction f as) =
>         names f <> parens (commaSep $ map (valueExpr d) as)
>     tr (TRAlias t a) = sep [tr t, alias a]
>     tr (TRParens t) = parens $ tr t
>     tr (TRQueryExpr q) = parens $ queryExpr d q
>     tr (TRJoin t0 b jt t1 jc) =
>        sep [tr t0
>            ,if b then text "natural" else empty
>            ,joinText jt <+> tr t1
>            ,joinCond jc]
>     joinText jt =
>       sep [case jt of
>               JInner -> text "inner"
>               JLeft -> text "left"
>               JRight -> text "right"
>               JFull -> text "full"
>               JCross -> text "cross"
>           ,text "join"]
>     joinCond (Just (JoinOn e)) = text "on" <+> valueExpr d e
>     joinCond (Just (JoinUsing es)) =
>         text "using" <+> parens (commaSep $ map name es)
>     joinCond Nothing = empty

> maybeValueExpr :: Dialect -> String -> Maybe ValueExpr -> Doc
> maybeValueExpr d k = me
>       (\e -> sep [text k
>                  ,nest (length k + 1) $ valueExpr d e])

> grpBy :: Dialect -> [GroupingExpr] -> Doc
> grpBy _ [] = empty
> grpBy d gs = sep [text "group by"
>                ,nest 9 $ commaSep $ map ge gs]
>   where
>     ge (SimpleGroup e) = valueExpr d e
>     ge (GroupingParens g) = parens (commaSep $ map ge g)
>     ge (Cube es) = text "cube" <> parens (commaSep $ map ge es)
>     ge (Rollup es) = text "rollup" <> parens (commaSep $ map ge es)
>     ge (GroupingSets es) = text "grouping sets" <> parens (commaSep $ map ge es)

> orderBy :: Dialect -> [SortSpec] -> Doc
> orderBy _ [] = empty
> orderBy dia os = sep [text "order by"
>                  ,nest 9 $ commaSep $ map f os]
>   where
>     f (SortSpec e d n) =
>         valueExpr dia e
>         <+> (case d of
>                   Asc -> text "asc"
>                   Desc -> text "desc"
>                   DirDefault -> empty)
>         <+> (case n of
>                 NullsOrderDefault -> empty
>                 NullsFirst -> text "nulls" <+> text "first"
>                 NullsLast -> text "nulls" <+> text "last")

= utils

> commaSep :: [Doc] -> Doc
> commaSep ds = sep $ punctuate comma ds

> me :: (a -> Doc) -> Maybe a -> Doc
> me = maybe empty

> comment :: Comment -> Doc
> comment (BlockComment str) = text "/*" <+> text str <+> text "*/"
