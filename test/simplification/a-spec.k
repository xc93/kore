module VERIFICATION

    imports SIMPLIFICATION

    rule f(X:Int) => a requires X >Int 0 [simplification]
    rule f(X:Int) => b requires X <Int 0 [simplification]
    
endmodule

module A-SPEC

    imports VERIFICATION

    rule <k> f(X:Int) => a </k>

endmodule