Require Import compcert.lib.Maps.
Require Import compcert.common.AST.
Require Import compcert.common.Values.
Require Import compcert.common.Globalenvs.

Require Import msl.ageable.

Require Import sepcomp.semantics.
Require Import sepcomp.extspec.
Require Import sepcomp.step_lemmas.

Require Import veric.compcert_rmaps.
Require Import veric.juicy_mem.

Definition pures_sub (phi phi' : rmap) :=
  forall adr,
  match resource_at phi adr with
    | PURE k pp => resource_at phi' adr
                 = PURE k (preds_fmap (approx (level phi')) (approx (level phi')) pp)
    | _ => True
  end.

Lemma pures_sub_trans phi1 phi2 phi3 :
  (level phi3 <= level phi2)%nat ->
  pures_sub phi1 phi2 ->
  pures_sub phi2 phi3 ->
  pures_sub phi1 phi3.
Proof.
  intros lev S1 S2. intros l; spec S1 l; spec S2 l.
  destruct (phi1 @ l); auto.
  rewrite S1 in S2. rewrite S2.
  f_equal.
  rewrite (compose_rewr (preds_fmap _ _)).
  rewrite preds_fmap_comp.
  rewrite approx_oo_approx'; auto.
  rewrite approx'_oo_approx; auto.
Qed.

Lemma pures_sub_refl phi : pures_sub phi phi.
Proof.
  intros l.
  destruct (phi @ l) eqn:E; auto; f_equal.
  pose proof E as E_.
  rewrite <-resource_at_approx, E_ in E. simpl in E.
  congruence.
Qed.

Definition pures_eq (phi phi' : rmap) :=
  pures_sub phi phi' /\
  (forall adr,
   match resource_at phi' adr with
    | PURE k pp' => exists pp, resource_at phi adr = PURE k pp
    | _ => True
  end).

Lemma pures_eq_refl phi : pures_eq phi phi.
Proof.
  split. apply pures_sub_refl. intros l; destruct (phi @ l); eauto.
Qed.

Lemma pures_eq_trans phi1 phi2 phi3 :
  level phi3 <= level phi2 ->
  pures_eq phi1 phi2 ->
  pures_eq phi2 phi3 ->
  pures_eq phi1 phi3.
Proof.
  intros lev [S1 E1] [S2 E2]; split. apply pures_sub_trans with phi2; auto.
  intros l; spec E1 l; spec E2 l.
  destruct (phi3 @ l); auto. destruct E2 as (pp, E2). rewrite E2 in E1; auto.
Qed.

Section juicy_safety.
  Context {G C Z:Type}.
  Context (genv_symb: G -> PTree.t block).
  Context (Hcore:@CoreSemantics G C juicy_mem).
  Variable (Hspec:external_specification juicy_mem external_function Z).
  Definition Hrel n' m m' :=
    n' = level m' /\
    (level m' < level m)%nat /\
    pures_eq (m_phi m) (m_phi m').
  Definition safeN := @safeN_ G C juicy_mem Z genv_symb Hrel Hcore Hspec.
End juicy_safety.
