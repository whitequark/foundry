%token <Unicode.utf8s>      Name_Local
%token <Unicode.utf8s>      Name_Global
%token <Unicode.utf8s>      Name_Label
%token <Unicode.utf8s>      Name_Syntax
%token                      Name_Debug

%token <Unicode.utf8s>      Lit_String
%token <Fy_big_int.big_int> Lit_Integer

%token <Syntax.exprs>       Syntax_Exprs
%token <Syntax.expr>        Syntax_Lambda

%token LParen
%token RParen
%token LBrack
%token RBrack
%token LBrace
%token RBrace
%token Comma
%token Equal
%token Arrow
%token FatArrow
%token Question
%token Star
%token StarStar
%token X

%token Type
%token Tvar
%token Nil
%token True
%token False
%token Boolean
%token Int
%token Signed
%token Unsigned
%token Symbol
%token String
%token Option
%token Array
%token Storage
%token Environment
%token Lambda
%token Closure
%token Class
%token Mixin
%token Package
%token Instance

%token Immutable
%token Mutable
%token Meta_mutable
%token Dynamic

%token Parent
%token Bindings

%token Local_env
%token Type_env
%token Const_env
%token Args
%token Default
%token Body

%token Metaclass
%token Objectclass
%token Ancestor
%token Parameters
%token Ivars
%token Methods
%token Prepended
%token Appended
%token Constants

%token Empty

%token Function
%token Jump
%token Jump_if
%token Return
%token Phi
%token Select
%token Frame
%token Lvar_load
%token Lvar_store
%token Ivar_load
%token Ivar_store
%token Call
%token Tuple_extend
%token Tuple_concat
%token Record_extend
%token Record_concat
%token Specialize
%token Primitive

%token Map

%token EOF

%%
