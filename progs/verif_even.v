Require Import floyd.proofauto.
Require Import progs.even.
Instance CompSpecs : compspecs.
Proof. make_compspecs prog. Defined.
Definition Vprog : varspecs. mk_varspecs prog. Defined.

Local Open Scope assert.

Definition odd_spec :=
 DECLARE _odd
  WITH z : Z, b: unit
  PRE [ _n OF tuint]
    PROP(0 <= z <= Int.max_signed) LOCAL(temp _n (Vint (Int.repr z))) SEP()
  POST [ tint ]
    PROP() LOCAL(temp ret_temp (Vint (if Z.odd z then Int.one else Int.zero))) SEP().

Definition even_spec :=
 DECLARE _even
  WITH z : Z
  PRE [ _n OF tuint]
    PROP(0 <= z <= Int.max_signed) LOCAL(temp _n (Vint (Int.repr z))) SEP()
  POST [ tint ]
    PROP() LOCAL(temp ret_temp (Vint (if Z.even z then Int.one else Int.zero))) SEP().

Definition main_spec :=
 DECLARE _main
  WITH z : Z, v : val
  PRE [ ] PROP() LOCAL() SEP ()
  POST [ tint ]
    PROP() LOCAL(temp ret_temp (Vint (if Z.even 42 then Int.one else Int.zero))) SEP().


Definition Gprog : funspecs :=
     ltac:(with_library prog [odd_spec; even_spec; main_spec]).

Lemma body_even : semax_body Vprog Gprog f_even even_spec.
Proof.
start_function.
forward_if (PROP (z > 0) LOCAL (temp _n (Vint (Int.repr z))) SEP ()).
*
 forward.
*
 forward. entailer!.
* normalize.
  forward_call (z-1, tt).
  (* Prove that PROP precondition is OK *)
  repable_signed.
  (* After the call *)
  forward.
  entailer!.
  rewrite Z.odd_sub; simpl.
  case_eq (Z.odd z); rewrite Zodd_even_bool; destruct (Z.even z); simpl; try congruence.
Qed.

Lemma body_main : semax_body Vprog Gprog f_main main_spec.
Proof.
start_function.
forward_call (42).
repable_signed.
forward.
Qed.

Definition Espec := add_funspecs NullExtension.Espec (ext_link_prog prog) Gprog.
Existing Instance Espec.

Lemma temp_make_ext_rval_e:
  forall gx v v',
   locald_denote (temp ret_temp v) (make_ext_rval gx v') ->
   v <> Vundef ->
   v' = Some v.
Proof.
intros.
hnf in H. subst.
unfold make_ext_rval, eval_id in *.
destruct v'; simpl in *; auto.
contradiction H0; auto.
Qed.

Lemma all_funcs_correct: semax_func Vprog Gprog (prog_funct prog) Gprog.
Proof.
unfold Gprog, prog, prog_funct.
simpl.
 repeat (apply semax_func_cons_ext_vacuous; [reflexivity | reflexivity | ]);
semax_func_cons_ext. {
  destruct x.
 rewrite <- insert_local.
 rewrite lower_andp.
 apply derives_extract_prop; intro.
 hnf in H0. rewrite retval_ext_rval in H0. rewrite <- H0. entailer!.
}
semax_func_cons body_even.
semax_func_cons body_main.
Qed.

