grammar stlc;


imports core:monad;


Restricted inherited attribute gamma::[Pair<String Type>];
Implicit synthesized attribute typ::Either<String Type>;
{-A second try to avoid these problems:  We only add an error from the
  top if the two children's types are not errors.-}
Unrestricted synthesized attribute errors::[String];

--nondeterministic evaluation
Implicit synthesized attribute next::[Expression];
Restricted inherited attribute substV::String;
Restricted inherited attribute substE::Expression;
Restricted synthesized attribute substed::Expression;
Restricted synthesized attribute isvalue::Boolean;

--deterministic evaluation
Implicit synthesized attribute nextStep::Maybe<Expression>;  --synthesized attribute nextStep::~Implicit Maybe<Expression>;

Unrestricted synthesized attribute pp::String;



function lookupType
Maybe<Type> ::= name::String gamma::[Pair<String Type>]
{
  return if null(gamma)
         then nothing()
         else if head(gamma).fst == name
              then just(head(gamma).snd)
              else lookupType(name, tail(gamma));
}


synthesized attribute steps::[[Expression]]; --nondeterministic
synthesized attribute singleSteps::[Expression]; --deterministic
nonterminal Root with pp, typ, next, errors, steps, nextStep, singleSteps;

abstract production root
top::Root ::= e::Expression
{
  restricted e.gamma = [];
  implicit top.typ = e.typ;
  unrestricted top.errors = e.errors;

  implicit top.next = e.next;

  unrestricted top.pp = e.pp;

  top.steps = if null(e.next)
              then [[e]]
              else foldr(\x::Expression r::[[Expression]] -> map(\y::[Expression] -> e::y, root(x).steps) ++ r, [], e.next);

   implicit top.nextStep = e.nextStep;

   top.singleSteps = case e.nextStep of
                     | just(x) -> e::root(x).singleSteps
                     | nothing() -> [e]
                     end;
}



nonterminal Expression with
   gamma, typ, errors,
   next, substV, substE, substed, isvalue,
   nextStep,
   pp;

abstract production var
top::Expression ::= name::String
{
  implicit top.typ = case lookupType(name, top.gamma) of
                     | just(x) -> right(x)
                     | nothing() -> left("Unknown variable " ++ name)
                     end;
  unrestricted top.errors = case top.typ of
                             | left(s) -> [s]
                             | _ -> []
                             end;

  restricted top.isvalue = false;
  implicit top.next = ;

  restricted top.substed = if top.substV == name
                           then top.substE
                           else top;

  implicit top.nextStep = ;

  unrestricted top.pp = name;
}


abstract production abs
top::Expression ::= name::String ty::Type body::Expression
{
  restricted body.gamma = [pair(name, ty)] ++ top.gamma;
  implicit top.typ = arrow(ty, body.typ);
  unrestricted top.errors = case top.typ, body.typ of
                            | left(s), right(_) -> [s] ++ body.errors
                            | _, _ -> body.errors
                            end;

  restricted top.isvalue = true;
  implicit top.next = ;

  restricted body.substV = top.substV;
  restricted body.substE = top.substE;
  restricted top.substed = if top.substV == name
                         then top
                         else abs(name, ty, body.substed);

  implicit top.nextStep = ;

  unrestricted top.pp = "lambda " ++ name ++ ":" ++ ty.pp ++ "." ++ body.pp;
}


abstract production app
top::Expression ::= t1::Expression t2::Expression
{
  restricted t1.gamma = top.gamma;
  restricted t2.gamma = top.gamma;
  implicit top.typ = case t1.typ of
                     | arrow(ty1, ty2) when tyEq(ty1, t2.typ) -> ty2
                     | arrow(_, _) -> left("Application type mismatch")
                     | _ -> left("Non-function applied")
                     end;
  unrestricted top.errors = case top.typ, t1.typ, t2.typ of
                            | left(s), right(ty1), right(ty2) -> [s] ++ t1.errors ++ t2.errors
                            | _, _, _ -> t1.errors ++ t2.errors
                            end;

  restricted top.isvalue = false;
  implicit top.next = case_any t1, t2 of
                      | abs(n, t, b), v when v.isvalue ->
                        decorate b with {substV=n; substE=v;}.substed
                      | _, _ -> app(t1.next, t2)
                      | _, _ -> app(t1, t2.next)
                      end;

  restricted t1.substV = top.substV;
  restricted t2.substV = top.substV;
  restricted t1.substE = top.substE;
  restricted t2.substE = top.substE;
  restricted top.substed = app(t1.substed, t2.substed);

  implicit top.nextStep = case t1, t2 of
                          | abs(n, t, b), v when v.isvalue ->
                            decorate b with {substV=n; substE=v;}.substed
                          | v1, _ when !v1.isvalue -> app(t1.nextStep, t2)
                          | _, _ -> app(t1, t2.nextStep)
                          end;

  unrestricted top.pp = "(" ++ t1.pp ++ ") (" ++ t2.pp ++ ")";
}


abstract production or
top::Expression ::= t1::Expression t2::Expression
{
  restricted t1.gamma = top.gamma;
  restricted t2.gamma = top.gamma;
  implicit top.typ = case t1.typ, t2.typ of
                     | bool(), bool() -> bool()
                     | _, _ -> left("Both disjuncts must be of type Bool")
                     end;
  unrestricted top.errors = case top.typ, t1.typ, t2.typ of
                            | left(s), right(_), right(_) -> [s] ++ t1.errors ++ t2.errors
                            | _, _, _ -> t1.errors ++ t2.errors
                            end;

  restricted top.isvalue = false;
  implicit top.next = case_any t1, t2 of
                      | tru_a(), _ -> tru_a()
                      | _, tru_a() -> tru_a()
                      | fals_a(), fals_a() -> fals_a()
                      | _, _ -> or(t1.next, t2)
                      | _, _ -> or(t1, t2.next)
                      end;

  restricted t1.substV = top.substV;
  restricted t2.substV = top.substV;
  restricted t1.substE = top.substE;
  restricted t2.substE = top.substE;
  restricted top.substed = or(t1.substed, t2.substed);

  implicit top.nextStep = case t1, t2 of
                          | tru_a(), _ -> tru_a()
                          | fals_a(), _ -> t2
                          | _, _ -> or(t1.nextStep, t2)
                          end;

  unrestricted top.pp = "(" ++ t1.pp ++ ") || (" ++ t2.pp ++ ")";
}


abstract production and
top::Expression ::= t1::Expression t2::Expression
{
  restricted t1.gamma = top.gamma;
  restricted t2.gamma = top.gamma;
  implicit top.typ = case t1.typ, t2.typ of
                     | bool(), bool() -> bool()
                     | _, _ -> left("Both conjuncts must be of type Bool")
                     end;
  unrestricted top.errors = case top.typ, t1.typ, t2.typ of
                            | left(s), right(ty1), right(ty2) -> [s] ++ t1.errors ++ t2.errors
                            | _, _, _ -> t1.errors ++ t2.errors
                            end;

  restricted top.isvalue = false;
  implicit top.next = case_any t1, t2 of
                      | tru_a(), tru_a() -> tru_a()
                      | _, fals_a() -> fals_a()
                      | fals_a(), _ -> fals_a()
                      | _, _ -> and(t1.next, t2)
                      | _, _ -> and(t1, t2.next)
                      end;

  restricted t1.substV = top.substV;
  restricted t2.substV = top.substV;
  restricted t1.substE = top.substE;
  restricted t2.substE = top.substE;
  restricted top.substed = and(t1.substed, t2.substed);

  implicit top.nextStep = case t1, t2 of
                          | tru_a(), _ -> t2
                          | fals_a(), _ -> fals_a()
                          | _, _ -> and(t1.nextStep, t2)
                          end;

  unrestricted top.pp = "(" ++ t1.pp ++ ") && (" ++ t2.pp ++ ")";
}


abstract production tru_a
top::Expression ::=
{
  implicit top.typ = bool();
  unrestricted top.errors = [];

  restricted top.isvalue = true;
  implicit top.next = ;

  restricted top.substed = top;

  implicit top.nextStep = ;

  unrestricted top.pp = "true";
}


abstract production fals_a
top::Expression ::=
{
  implicit top.typ = bool();
  unrestricted top.errors = [];

  restricted top.isvalue = true;
  implicit top.next = ;

  restricted top.substed = top;

  implicit top.nextStep = ;

  unrestricted top.pp = "false";
}


abstract production not
top::Expression ::= e::Expression
{
  restricted e.gamma = top.gamma;
  implicit top.typ = case e.typ of
                     | bool() -> bool()
                     | _ -> left("Not requires an argument of type Bool")
                     end;
  unrestricted top.errors = case top.typ, e.typ of
                            | left(s), right(_) -> [s] ++ e.errors
                            | _, _ -> e.errors
                            end;

  restricted top.isvalue = false;
  implicit top.next = case_any e of
                      | tru_a() -> fals_a()
                      | fals_a() -> tru_a()
                      | _ -> not(e.next)
                      end;

  restricted e.substV = top.substV;
  restricted e.substE = top.substE;
  restricted top.substed = not(e.substed);

  implicit top.nextStep = case e of
                          | tru_a() -> fals_a()
                          | fals_a() -> tru_a()
                          | _ -> not(e.nextStep)
                          end;

  unrestricted top.pp = "!(" ++ e.pp ++ ")";
}




nonterminal Type with pp;

abstract production arrow
top::Type ::= t1::Type t2::Type
{
  top.pp = "(" ++ t1.pp ++ ") -> " ++ t2.pp;
}


abstract production bool
top::Type ::=
{
  top.pp = "Bool";
}



function tyEq
Boolean ::= t1::Type t2::Type
{
  return case t1, t2 of
         | bool(), bool() -> true
         | arrow(t11, t12), arrow(t21, t22) ->
           tyEq(t11, t21) && tyEq(t12, t22)
         | _, _ -> false
         end;
}