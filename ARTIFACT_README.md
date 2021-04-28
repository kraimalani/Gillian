# Artifact: Gillian, Part II - Real World Verification for JavaScript and C

Welcome to the artifact README for the CAV 2021 paper: "Gillian, Part II: Real-World Verification for JavaScript and C". In this document, we describe how to use this artifact to reproduce the results presented in the paper.

## Table of contents

[TOC]

## Reproducing the results

To make the task simple, we created a `Makefile` that lets you run everything. In particular, in the root of the `Gillian` folder, running:

- `$ make c` will verify the correctness of all of the functions that were specified in the C aws-encryption-sdk. The three most important ones are: `aws_cryptosdk_enc_ctx_deserialize`, `parse_edk`, and the main deserialisation function, `aws_cryptosdk_hdr_parse`. This verification takes approximately 14 minutes on .
- `$ make js` will verify the correctness of all of the functions that were specified in the JS aws-encryption-sdk. The three most important ones are: `decodeEncryptionContext`, `deserializeEncryptedDataKeys`, and the main deserialisation function, `deserializeMessageHeader`. This verification takes approximately 45 seconds.
- `$ make c-proc PROC=function_name` will run the verification of only the C function whose identifier is `function_name`, if it has a specification. For example, `$ make c-proc PROC=parse_edk` verifies the `parse_edk` function.
- `$ make c-lemma LEMMA=lemma_name` will run the proof of the C lemma whose identifier is `lemma_name`, if such a lemma exists.


In addition to this, there exists another `Makefile` that allows you to reproduce the three bugs that we found in the C code. First go into the following directory:
```bash
$ cd Gillian-C/examples/amazon/bug
```
where you have three rules at your disposal:
```bash
$ make header-bug
$ make string-bug
$ make byte-cursor-ub
```

The first rule demonstrates the found logical error in the parsing of the header; the second demonstrates the found over-allocation; and the third demonstrates the found undefined behaviour.

Finally, there exists another `Makefile` that lets you reproduce the failed verification for the two bugs discovered in JavaScript:

```shell
$ cd ../../../.. # Go back to the Gillian root
$ cd Gillian-JS/Examples/amazon/bug
```
where you have two rules at your disposal:

```bash
$ make proto-bug
$ make frozen-bug
```

The first rule demonstrates the found prototype poisoning bug; and the second demonstrates the bug in which the encryption context is returned non-frozen.




## Gillian in more detail

### What does Gillian say ?

When running Gillian, several steps occur :

- First of all the code is parsed and compiled. The Gillian instantiation (C or JS) provides information on how to compile the program to GIL, by implementing a signature called `ParserAndCompiler.S`, declared in `GillianCore/parserAndCompiler/ParserAndCompiler.ml`. During this phase, Gillian will print `Parsing and Compiling...`.

- Secondly, Gillian performs some preprocessing on the "logic" annotations. For example, it will inline the definition of any non-recursive predicate in the specifications pre-conditions and post-conditions. This phase is usually fast, but can get a bit slower when predicates are very complex (which is the case the predicates defined in the `header.c` file). During this phase, Gillian will print `Preprocessing...`

- Once preprocessing is done, Gillian will start collecting the tests. One test corresponds to one function specification to verify or to one lemma to prove. This phase is usually very fast  During this phase, Gillian will print

  ```
  Obtaining specs to verify...
  Obtaining lemmas to verify...
  Obtained X symbolic tests in total
  ```

- Finally, Gillian prints the time spent in the three first phases, and starts running the tests one by one. Each test corresponds either to a lemma or a function specification. Gillian will indicate which one it is currently proving. Moreover, when verifying function specifications. Gillian will print a bit more information.
  During symbolic execution, it will print for each branch it has taken
  - `n` when the function's end has been reached in "normal mode".

  - `e` when the function's end has a been reached in "error mode". Error mode does not exist in C and is used to model the way functions end when using `throw` in JavaScript.

    While analysing the different results obtained for that branch, it will print

  - `s` when one of the test ended on a return and unified successfully against the specified post-condition.

  - `f` if the symbolic execution has failed early or has ended but did not unify successfully against the post condition
  Finally, after all of that has been done Gillian prints `Failure` or `Success`, the latter corresponding to every branch finishing as expected and unifying against the desired post-condition.

### Can it say more ?

It is possible to ask Gillian to give more details by writing varying degrees of details in a log file. That behaviour is controlled by the `-l` command line argument. Notice that in the provided Makefiles, every command specifies `-l disabled`, it would be possible to add `-l normal`. The default behaviour (no flag) is equivalent to `-l verbose`. Debugging a Gillian execution is an art that requires a lot of practice and making it easily debuggable is an ongoing project.

Because producing the log file is expensive in terms of ressource and can produce up to several gigabytes in data, if the reader wants to see what kind of information is contained, we advise to run a small example with the `-l normal` flag.

### The command line interface

Gillian is the core framework in which we simply plug information about compilation and memory models for target languages. Therefore, all binaries produced by using the Gillian framework have a quite similar command-line interface. It is possible to see the details of possible arguments by running the following commands from the Gillian root folder:

```shell
$ esy x gillian-c --help
$ esy x gillian-js --help
```

The reader will find that both executable exposes at least four sub-commands  : `compile`,  `wpst`, `verify` and `act`:

- `compile` allows one to generate the GIL files from a target-language program, second corresponds to whole program.
- `wpst` corresponds to whole-program symbolic testing, presented in our previous paper entitled Gillian Part I, published at PLDI2020. It is out of the scope of this paper.
- `verify` corresponds to full verification (including specifications and abstractions). *It is the only command that is in the scope of the current paper*.
-  `act` corresponds to automatic compositionnal testing, which uses bi-abduction in the style of Infer. It is out of the scope of this paper.

Because `verify` is the command that we're interested in for this artifact, we'll give a bit more details about it.
First of all, the reader is invited to run:

```sh
$ esy x gillian-c verify --help
```

Not every argument is relevant to this artifact. We will only detail the arguments that are used in the Makefiles.

- `-l`, alias for `--logging` has been detailed earlier

- `--lemma` and `--proc` are used to specify which lemmas or procedures to verify. To run several procs, the flags can be used several times. For example

  ```sh
  $ esy x gillian-c verify test.c --proc function_a --proc function_b
  ```

- `--no-lemma-proof` allows for lemmas to be missing a proof. Lemmas with proof with still be proven, but lemmas can be used even if they don't have proofs. In the case of this artifact, we need to apply lemmas that correspond to parts of the code that we have axiomatised (as explained in the caveats section in the paper).
- (For C only) `--fstruct-passing` is a flag that is passed directly to `CompCert` and is detailed in [its manual](https://compcert.org/man/manual003.html#sec41). It enables the following feature: "Support functions that take parameters and return results of composite types (struct or union types) by value".

## C : reading annotations and understanding the bugs

### Reading Gillian-C annotations: Predicates

Let us dive into how to read the annotations in C. We recommend that you open the code in VSCode, for which we have developped a small syntax highlighting extension that makes annotations more readable.

```sh
$ code . // In the Gillian root folder
```

We will now walk the reader through a few elements written in `Gillian-C/examples/amazon/byte_buf.c`.

First of all, comments starting with `/*@` are parsed by the Gillian-C parser as logic annotations. Such comments are used to define predicates, lemmas and specifications.

In particular, let us give details about the first predicate that is defined called `valid_aws_byte_cursor_ptr`. It describes an element of type `struct aws_byte_cursor` on which some constraints have been applied. It can be seen as a form of invariant that should be preserved whenever an element of that type is constructed or modified.

The `struct aws_byte_cursor` type is defined in `Gillian-C/examples/amazon/byte_buf.h` as follows:

```c
struct aws_byte_cursor {
    size_t len;
    uint8_t *ptr;
};
```

The reader may recognise that such a cursor is an implementation of an array slice : the cursor contains a pointer `ptr` that can be anywhere inside an array, and a length `len`. It should always be possible to read `len` bytes at address `ptr`.
The original AWS code for this structure does contain annotations for concrete tests that try to enforce such a behaviour. Every function that uses an aws_byte_cursor ends with a post-condition check of the form

```c
AWS_POSTCONDITION(aws_byte_buf_is_valid(cursor))
```

where `aws_byte_buf_is_valid` (and what it depends on) is defined as follows:

```c
/**
 * The C runtime does not give a way to check these properties,
 * but we can at least check that the pointer is valid. */
#define AWS_MEM_IS_READABLE(base, len) (((len) == 0) || (base))
bool aws_byte_cursor_is_valid(const struct aws_byte_cursor *cursor) {
    return cursor != NULL &&
           ( (cursor->len == 0) ||
             (cursor->len > 0 && cursor->ptr && AWS_MEM_IS_READABLE(cursor->ptr, cursor->len))
           );
}
```

This predicate checks that the cursor is not NULL, and that it points to a structure that either has length 0 (and we don't care what's in the pointer because nothing will be read ever), or to something that has length > 0 and a non-NULL pointer. The comment about limitations in the C runtime is [also extracted from the AWS code itself](https://github.com/awslabs/aws-c-common/blob/1143dd566748e3d30f301d592911a2743205420c/include/aws/common/assert.h#L105).

Gillian-C can overcome this limitation by providing the necessary expressivity to talk about what's in memory. The predicate is defined as follows:

```c
pred nounfold valid_aws_byte_cursor_ptr(+cur, length, buffer: List, alpha) {
  (cur -> struct aws_byte_cursor { long(0); buffer }) *
  (length == 0) * (alpha == nil);

  (cur -> struct aws_byte_cursor { long(length); buffer }) * (0 <# length) *
  ARRAY(buffer, char, length, alpha) * (length == len alpha) *
  (length <=# MAX_IDX_SIZE)
}
```

It contains two definitions, separated by a semi-colon.

The first definition contains three bits of information, joined by the [`separating conjunction`](https://en.wikipedia.org/wiki/Separation_logic)

- `cur -> struct aws_byte_cursor { long(0); buffer })`, which says that `cur` is a valid pointer to a structure of type `struct aws_byte_cursor`, of which the `len` field has value `long(0)` (the type corresponds to the internal type [used by CompCert](https://compcert.org/doc/html/compcert.common.AST.html#Tlong) in x64 mode to interpret `size_t`).
- It says that, in this case of the predicate the length is 0 and the represented list of bytes is `nil`, which is an alias for the empty list. Note that `length` corresponds to the mathematical value representing the length.
- It says nothing about `buffer`, but the `-> struct xxx` annotation is compiled to a predicate in GIL that indicates the layout of the structure in memory, and this predicates does contain the information that buffer is either a pointer or `NULL`.

The second definition is similar to the first one, but specifies the non-empty case:

- `length`, (the mathematical value contained by the C value in `cur->len`) has to be strictly greater than 0, and strictly smaller than the maximum indexable size.
- `buffer` has to be a valid pointer that points to an array of bytes in memory (the type being denoted by `char`), of size `length` and content `alpha`.

The use of the separating conjunction in Gillian-C is particularly interesting: this predicates does not only describe the shape and value of data in memory, it also gives **ownership** of the array slice to the pointer `cur`. Indeed, while in C it would be possible to have two cursors `cur1` and.`cur2` pointing to the same slice, it would *not* be possible to write the follwing assertion:

```c
valid_aws_byte_cusor_ptr(cur1, #b, #alpha) * valid_aws_byte_cursor(cur2, #b, #alpha)
```

This idea of ownership is used intensively in modern languages such as Rust.

Finally, note that predicates in Gillian can have additional specifiers placed in their headers:

- `nounfold` means that, although this predicate is not recursive, it should not be unfolded automatically during preprocessing.
- `pure` means that this predicate does not specify spatial ressource, and it can therefore be duplicated (i.e. if the predicate `is_NULL(x)` is marked as pure, Gillian will understand without unfolding it that `is_NULL(x) * is_NULL(x)` is a valid assertion).

### Reading Gillian-C annotations: Specifications and Lemmas

In Gillian-C, function specifications are written with the following syntax:

```c
[axiomatic?] spec [function_name] ([arg1], ..., [argn]) {
   requires: [Pre: assertion]
   ensures: [Post1: assertion]; [Post2: assertion]; ... [Postn: assertion]
}
```

which means that it is a specification for `function_name` with the given arguments `arg1, .. argn`, which has precondition `Pre` and several possible post-conditions `Post1` to `Postn` separated by semi-colons. It is also possible to have several specifications for the same fonction, in which case there will be several `requires/ensures` pairs separated by the keyword `OR`. If the `axiomatic` keyword is added before the `spec` keyword, Gillian will not try to prove the spec. We use it for most `array_list` functions and all `hash_table` functions.

Similarly, in Gillian-C, a lemma is simply a specification for which the proof is not a function, but a list of *logic commands*. A logic command is a GIL command that transforms the state S1 into another state S2, such that S1 => S2. As opposed to actual commands, they do not *change* the state. The syntax is as follows:

```
lemma [lemma_name] ([arg1], ..., [argn]) {
   hypothesis: [Pre: assertion]
   conclusions: [Post1: assertion]; [Post2: assertion]; ... [Postn: assertion]
   proof: [logic_commands]
}
```

The proof is optional, since we may not be able to write proofs when lemmas are using axiomatic predicates.

### Reading Gillian-C annotations: Tactics

Most verification proofs require human help. For example, it is necessary to write loop invariants or to ask Gillian to unfold a specific predicate. These tactics are just logic commands that will be called in the middle of execution. If the reader is interested, the type definition corresponding to the logic commands in C (later compiled to logic commands in GIL) is in `Gillian-C/lib/cLogic.ml`:

```ocaml
type t =
    | If         of CExpr.t * t list * t list (** Conditional execution of logic command *)
    | Unfold     of {
        pred : string;
        params : CExpr.t list;
        bindings : (string * string) list option;
        recursive : bool;
      } (** Unfolding of a specific predicate *)
    | Unfold_all of string (** Recursively unfold all predicates with the given name (with a fuel). *)
    | Fold       of string * CExpr.t list (** Fold a predicate *)
    | Apply      of string * CExpr.t list (** Apply a lemma *)
    | Assert     of CAssert.t * string list
        (** Assert for verification, takes an assertion and binders *)
    | Branch     of CFormula.t (** The symbolic engine should branch on the given formula *)
    | Invariant  of {
        assertion : CAssert.t;
        bindings : string list;
      } (** Loop invariant *)
    | SymbExec (** Ignore the next function specification and symbolically execute instead *)
```

### Understanding the bugs we found

We found three bugs in the AWS implementation. We already explained earlier how to reproduce those bugs. In this section, for each bug, we explain how it can happen, show how we fixed it and give the link to the Github issue that was filled.

#### A potential undefined behaviour in aws_byte_cursor_advance

As explained earlier, an `aws_byte_cursor` is a kind of abstraction that lets the user consume a buffer while always knowing how much memory is left. The function `aws_byte_cursor_advance` has the following documentation:

```c
/**
 * Tests if the given aws_byte_cursor has at least len bytes remaining. If so,
 * *buf is advanced by len bytes (incrementing ->ptr and decrementing ->len),
 * and an aws_byte_cursor referring to the first len bytes of the original *buf
 * is returned. Otherwise, an aws_byte_cursor with ->ptr = NULL, ->len = 0 is
 * returned.
 *
 * Note that if len is above (SIZE_MAX / 2), this function will also treat it as
 * a buffer overflow, and return NULL without changing *buf.
 */
struct aws_byte_cursor aws_byte_cursor_advance(struct aws_byte_cursor *const cursor, const size_t len);
```

In the case where the operation is estimated to be valid, the following operation is performed:

```c
cursor->ptr += len;
```

The issue is that if `ptr` is NULL, then the tests that checks if "the cursor has at least len bytes remaining" still passes, in which case the operation `NULL + 0` is performed. Although most compiler will not complain, this is technically an undefined behaviour according to the C specification.

There are several ways of fixing this issue. We believe that is is not an implementation error but a documentation / specification issue, i.e. the function documentation should specify that the function should never be called with a cursor that contains a `NULL` pointer if the length passed as argument 0. In all the code we analysed, that pre-condtion was respected. Therefore, we decided to add the following formula to the precondition that we wrote:

```
((0 <# #length) || (not (#buffer == NULL)))
```

Link: https://github.com/awslabs/aws-c-common/issues/771

#### Over-allocation in aws_string

The AWS standard library for C (called `aws-c-common` and is heavily used in the encryption SDK) defines a type `struct aws_string`.
It is an abstraction over raw C strings in order to make them safer to manipulate.
It is defined in `string.h`:

```c
struct aws_string {
    struct aws_allocator *const allocator;
    const size_t len;
    /* give this a storage specifier for C++ purposes. It will likely be larger after init. */
    const uint8_t bytes[1];
};
```

It contains :

- an allocator, used if one ever needs to use a customised function to delete the string;
- a length, used to check that one is never reading past the size of the string, and to retrieve the length in O(1); and
- an array of bytes that contains the actual string.

Note that this structure is defined using an ambiguous feature of : the last element is a flexible array member. In order to allocate such a structure, one needs to know the size of the array and add it to the size of the remaining elements. In the buggy code, this operation is done in some code that is mostly equivalent to this:

```c
struct aws_string *str = malloc(sizeof(struct aws_string) + 1 + length);
```

This is indeed what one would expect : size of the structure + length of the string + 1 byte for the null character `\0` terminating the string. However, because the flexible array member is specified using `bytes[1]`, `sizeof` gives it a size of `1 byte`. Because of alignment constraints in C, the size of the structure is given as `24` instead of `16`. Therefore, every allocated aws_string has 8 too many bytes.

It is quite a complex bug to fix because of the inconsistent behaviour of flexible array members between C and C++, as well as between different versions of C. For verification to pass, we decided on a fix that is correct in most C versions (including CompCert C) but is still ambiguous in C++, and removed the size specifier.

We detected that bug because thes structure created by the constructore could not unify against the the predicate we manually wrote to describe the expected layout in memory.

Link: https://github.com/awslabs/aws-c-common/issues/776

#### Wrong aad_len can be accepted by hdr_parse.

This issue is probably the most worrisome: there is a bug in the way the `aws_cryptosdk_hdr_parse` function parses the encyption context.

It starts by calling `aws_byte_cursor_advance` to read the encryption context's length (called `aad_len`). However, it does not check the returned value after that call. As said in the description of the first bug, if there isn't enough data to read the amount requested, the `advance` function will return a cursor containing a `NULL` buffer and a length of 0. Therefore, the function `aws_cryptosdk_enc_ctx_deserialize` will be passed a cursor that has `len = 0`, and will do nothing, returning `AWS_OP_SUCCESS`.

We are not security experts, but we believe a malicious header could be crafted such that it is in theory valid. Then, this header would be sent only partially to the server which would interpret it correctly as a very different header. More details are given in the Github issue.

Link: https://github.com/aws/aws-encryption-sdk-c/issues/695

## JS : reading annotations and understanding the bugs

!!!! PETARARRRRRRR !!!!!