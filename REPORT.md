# Final Project Report: SimpleLanguage

## How to run?

The entry point is located at `project-homework/src/interpreter.lua`
To invoke the interpeter, do `lua interpreter.lua < 'path-to-program'`

There are some example scripts provided in `project-homework/test/` directory.

## Language Syntax

The General Syntax of this Implementation is very similar to the syntax of the language developed during the main lessons in the course. There are some minor syntactic extensions, but these will be mentioned in the relevant sections of the next section.

## New Features/Changes

### Multi-Pass Compilation
The Compilation Phase is now split into three stages:
1. Every function is declared
2. Every function is compiled
3. Verify that every declared function is also defined

This preserves the opportunity to check at compile time if the function is declared, but eliminates the need for forward declarations.
Forward declarations are still present as a feature, to comply with the exercises specification. Forward declarations, however, introduce a possiblity for a function being declared but never defined, therefore introducing the possibility of calling a function that has no asscoiated code.

I've added a check to verify at compile time that every declared function is also defined. Moreover,
runtime can now signal if a call-site has no associated code.

### Ternary Expression

Example:
```
function main() {
    @absolute(-10);     #should print 10
}

function absolute(number) {
    return number >= 0 ? number : -number;
}
```
Note: This is an expression, and cannot be used as a statement.

### Function Overloading

The language supports function overloading based on number of function parameters.
Since the language also supports optional function parameter, there may be several overloads matching a function call.
Therefore, I've defined a number of overload selection rules and priorities:
Overload Selection Order:
1. Function with the same number of parameters as the number of arguments.
2. Function with one more formal parameter than number of arguments but only if it specifies default value for the last argument.
3. Error otherwise.

An Example:
```
function main() {
    @(main2()   == 1);      # should print 1
    @(main2(15) == 15);     # should print 1

    @(main3()   == 20);     # should print 1
    @(main3(20) == 40);     # should print 1
}


function main2() {
    return 1;
}

function main2(a);

function main2(a = 10) {
    return a;
}


function main3(a);

function main3(a = 10);

function main3(a) {
    return a*2;
}
```

Note: I also removed restriction which said that you cannot declare variables with the same name as functions.

### Run-time Type System (ish)

Runtime implements basic type checks and informs the user if opreation is applied to incompatible types.

Runtime types include:
1. Numbers - The set of Real numbers. 
2. Arrays - Fixed size data containers. Indexing starts at 1. Each cell can store arbitrary data type, except Null.
3. Null - Represents an absence of the value. Incomparable to anything. Arithmetic and Logical operators don't accept Null as thier operands. Cannot perform array access on Null. Cannot index array with Null.

### Concrete Types and Optional Types and Compile-time Type System (ish)

I find a concept of asbsence of the value to be quite useful in many cases, but only if it is explicit.
It may be very useful when dealing with global values that may not have been defined.
Therefore, I tried to implement something like this in the project.

#### Variables of Concrete/Optional Types

I've extended a local variable declarations with  '?' next to 'var' to signal that this is an optional variable:

```
var? optional1;         # implicitly initialized to 'null'
var? optional2 = null;  # explicitly initialized to 'null'
var? optional3 = 3;     # explicitly initialized to '3'

var concrete1;          # implicitly initialized to '0'
var concrete2 = null;   # Illegal!!! Compiler Error!
var concrete3 = 3;      # explicitly initialized to '3'
```

An Optional Value can contain everything that a Concrete Value can, plus a 'null' value.

A Global Variable Reference will always result in an Optional Value.

#### Functions with Optional Return Values

Function Declarations have been exteneded to specify if they return Optional or Concrete Type.
Example:
```
function main() {
    @(concrete());         # Should print '1'
    @(optional_null());    # Should print 'null'
    @(optional_of_1());    # Should print '1'
}

function concrete();
function optional_null()?;
function optional_of_1()?;

function concrete() {
    # return null;          # Illegal!!! Will not compile.
    return 1;
}

function optional_null()? {
    return null;
}

function optional_of_1()? {
    return 1;
}
```

#### Working with Optional Types

The Compile-time type system is somewhat different from runtime type-system.
It doesn't care about real types of individual values (such as number, array, null).
It only cares about if the value is of an optional or a concrete type, that is if it can contain a 'null'.

The type system implements the following rules:
1. All of the arithmetic, comparison, and logical operators only work with Concrete Types, that is, their operands cannot be 'null'.
2. Referencing a global variable will always result in a value of an Optional Type.
3. Referencing a local variable will result in a value of the type of the local variable.
4. Arguments to function calls must be of Concrete Type
5. Function call will result in a value of the type of the function return type.
6. Cannot perform array access on an Optional Type.
7. Cannot perform array access with an index of Optional Type.
8. Cannot write value of Optional Type into an array cell.

The language provides several operators to work with Optional Types:

1.  Operator '??' a.k.a 'is present':
        Syntax: `<atom> ??`
        Cannot be chained! (`<atom> ?? ??` is illegal)

    Returns 1 if `<atom>` is not null and 0 if it is null

    The operator has the presedence higher than exponent but less than atom, because its intention is to eliminate the propagation of 'null's though the expression.

Example:
```
function main() {
    # Should not compile (uncomment to verify)
    # return empty ?? ??;

    # Should return 1
    var? empty;
    var? not_empty = 2;
    return empty?? == 0 and not_empty?? == 1;
}
```

2.  Operator '?|' a.k.a 'or else':
        Syntax: `<atom> ?| <sum>`
        Right-associative.
        Can be chained.

    Returns `<atom>` if `<atom>` is not null, otherwise returns `<sum>`
        
    The syntax is inspired by '?' representing 'if' and '|' representing 'or'

    The operator has the same priority as '??'.

Example:
```
function main() {
    # Should return 1
    var? empty0;
    var? empty1;
    var? empty2 = 2;
    return empty0 ?| 1 == empty0 ?| empty1 ?| empty2??;
}
```

#### Notes about 'null' keyword
'null' keyword is an expression, but it cannot appear inside of another expression as a subexpression. This is done deliberately to minimize the use of this keyword. It is intended to be used in return statements (`return null`), or assignments to optional (or global) valiables (`something = null`). 

#### Working with Arrays
Because the type system doesn't allow to perform array access on an Optional Type, the user cannot perform array access on global variable. The user firstly needs to declare a new local variable of Concrete type, and assign array refence to that variable in a null-safe way (by using the newly introduced operators).

One way to simplify the user experience in this case is to implement something like "verify not null" operator (maybe of the form `<expression>!!`). The operator will essentially ensure that the execution will only continue if the `<expression>` is not null, otherwise the VM will throw an exception.
However, I don't quite like this idea because it defets the whole purpose of Optional Type in the first place, and can be abused easily.



## Future

I consider this whole project to be a playground for exploring ideas, and I sill have some to explore:

1. The language terribly lacks input capabilities. There is absolutely no way for the user to provide input when running the program. A quick way to fix it would be to forward command-line arguments to the main function. The general strategy would be to collect all the arguments and find an overload of the main function that accepts that many parameters, or maybe collect them in into an array, and do the same thing as all the other languages do.

2. Variadic functions is an interesting feature to consider, especially in conjunction with function overloading. Will need to extend overload selection policy to take this into account. I would probably assign the lowest selection priority to the variadic overload.

3. Improving Error Messages and Debug Output:
    Parsing errors:  parser can report position of an error, but it lacks context to report the reason of the error.
    Compiler errors: compiler reports reasons of the errors, but cannot report their position in the source code because this information is lost after parsing. Currently, I just print the part of the AST where error occured, but its not super helpful in immediately finding the root cause. A way to improve this is to make sure we also capture positional data associated with every AST node during parsing (using positional capture), storing it in our AST and using it during compilation.

    Debug output: there is a tiny debugging infrastructure present, you can configure logging level by altering the value of `log_level` variable inside the `interpreter.lua`, but this can be improved significantly.

4. (Epic) More datatypes and custom data types, like structs, enums.

## Self assessment

* Self assessment of your project: for each criteria described on the final project specs, choose a score (1, 2, 3) and explain your reason for the score in 1-2 sentences.
* Have you gone beyond the base requirements? How so?

| Rubric                | Score | Reason  |
|:----------------------|:-----:|:------------------------------------------------------------------------------------|
| Language Completeness |  2.5  | Exercises, Features and Challenges incorporated, but there is room for improvement  |
| Code Quality & Report |  2.0  | Code works, some attempt has been made to manage the complexity, report follows the guidelines. No automated tests. No documentation, except for this report. Error handling can benefit from more detailed mesages.   |
| Originality & Scope   |  2.0  | Minor language expansions and modificaions. But the code is not modular and does not follow open-closed principle.  |

## References

Found these articles quite interesting and easy to read:
* https://mukulrathi.com/create-your-own-programming-language/intro-to-type-checking/
* https://mukulrathi.com/create-your-own-programming-language/data-race-dataflow-analysis/
