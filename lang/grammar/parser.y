%{
package grammar

import (
    "io"
    "github.com/aybabtme/streamql/lang/ast"
)

var implicitSliceIdx = struct{}{}

%}

%token Dot
%token LeftBracket
%token RightBracket
%token LeftParens
%token RightParens
%token Colon
%token Pipe
%token Comma
%token Null
%token Bool
%token Identifier
%token String
%token Int
%token Float
%token LogOr
%token LogAnd
%token LogNot
%token CmpEq
%token CmpNotEq
%token CmpGt
%token CmpGtOrEq
%token CmpLs
%token CmpLsOrEq
%token NumAdd
%token NumSub
%token NumMul
%token NumDiv

// first eval arithmetic, then comparisons, then logic operations, then group in pipes
// order matters!
%right Pipe
%left LogOr                                  // only emits bools and only works on bools
%left LogAnd                                 // only emits bools and only works on bools
%left LogNot                                 // only emits bools and only works on bools
%nonassoc CmpEq, CmpNotEq                    // only emits bools, and _can_ compare bools
%nonassoc CmpGt, CmpGtOrEq, CmpLs, CmpLsOrEq // only emit bools, but _can't_ compare bools
%left NumAdd
%left NumSub
%left NumMul
%left NumDiv


%union {
    node   interface{}

    curID  int
    cur    tok
    err    error
}

%%
program: expr { cast(yylex).Expr = expr($1) }
       | ;

expr: literal         { $$ = literal($1) }
    | selector        { $$ = selector($1) }
    | unary_operator  { $$ = unaryOperator($1) }
    | binary_operator { $$ = binaryOperator($1) }
    | func_call       { $$ = funcCall($1) }
    | expr Pipe expr  { $$ = pipe($1, $3) }
    ;

literal: Bool   { $$ = emitBool($1) }
       | String { $$ = emitString($1) }
       | Int    { $$ = emitInt($1) }
       | Float  { $$ = emitFloat($1) }
       | Null   { $$ = emitNull($1) }
       ;

selector: Dot                                                       { $$ = emitNopSelector() }
        | Dot Identifier sub_selector                               { $$ = emitMemberSelector($2, $3) }
        | Dot LeftBracket RightBracket sub_selector                 { $$ = emitSliceSelectorEach($4) }
        | Dot LeftBracket expr RightBracket sub_selector            { $$ = emitMemberSelector($3, $5) }
        | Dot LeftBracket expr Colon expr RightBracket sub_selector { $$ = emitSliceSelector($3, $5, $7)}
        | Dot LeftBracket Colon expr RightBracket sub_selector      { $$ = emitSliceSelector(yySymType{node: implicitSliceIdx}, $4, $6)}
        | Dot LeftBracket expr Colon RightBracket sub_selector      { $$ = emitSliceSelector($3, yySymType{node: implicitSliceIdx}, $6)}
        ;
sub_selector: Dot Identifier sub_selector                           { $$ = emitMemberSelector($2, $3) }
            | LeftBracket RightBracket sub_selector                 { $$ = emitSliceSelectorEach($3) }
            | LeftBracket expr RightBracket sub_selector            { $$ = emitMemberSelector($2, $4) }
            | LeftBracket expr Colon expr RightBracket sub_selector { $$ = emitSliceSelector($2, $4, $6)}
            | LeftBracket Colon expr RightBracket sub_selector      { $$ = emitSliceSelector(yySymType{node: implicitSliceIdx}, $3, $4)}
            | LeftBracket expr Colon RightBracket sub_selector      { $$ = emitSliceSelector($2, yySymType{node: implicitSliceIdx}, $5)}
            | { $$ = yySymType{} };

unary_operator: LogNot expr                           { $$ = emitOpNot($2) }
              | LeftParens unary_operator RightParens { $$ = $2 }
              ;

binary_operator: expr LogAnd    expr                    { $$ = emitOpAnd($1, $3)    }
               | expr LogOr     expr                    { $$ = emitOpOr($1, $3)     }
               |      NumSub    expr                    { $$ = emitOpNeg($2)        }
               | expr NumAdd    expr                    { $$ = emitOpAdd($1, $3)    }
               | expr NumSub    expr                    { $$ = emitOpSub($1, $3)    }
               | expr NumDiv    expr                    { $$ = emitOpDiv($1, $3)    }
               | expr NumMul    expr                    { $$ = emitOpMul($1, $3)    }
               | expr CmpEq     expr                    { $$ = emitOpEq($1, $3)     }
               | expr CmpNotEq  expr                    { $$ = emitOpNotEq($1, $3)  }
               | expr CmpGt     expr                    { $$ = emitOpGt($1, $3)     }
               | expr CmpGtOrEq expr                    { $$ = emitOpGtOrEq($1, $3) }
               | expr CmpLs     expr                    { $$ = emitOpLs($1, $3)     }
               | expr CmpLsOrEq expr                    { $$ = emitOpLsOrEq($1, $3) }
               | LeftParens binary_operator RightParens { $$ = $2 }
               ;

func_call: Identifier LeftParens args RightParens { $$ = emitFuncCall($1, $3) }
         | Identifier                             { $$ = emitImplicitFuncCall($1) }
         ;
args: expr                                        { $$ = emitArg($1) }
    | expr Comma args                             { $$ = emitArgs($1, $3) }
    ;

%%

func cast(y yyLexer) *ast.AST { return y.(*Lexer).parseResult.(*ast.AST) }

func Parse(r io.Reader) (tree *ast.AST, err error) {
    tree = new(ast.AST)
    lex := NewLexerWithInit(r, func(l *Lexer) { l.parseResult = tree })
    // defer func() {
    //     r := recover()
    //     if r != nil {
    //         err = fmt.Errorf("%v", r)
    //     }
    // }()
    yyParse(lex)
    return tree, err
}
