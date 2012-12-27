Load loadpath.
Require Import 
 msl.base 
 veric.sim veric.step_lemmas veric.base veric.expr
 veric.extension veric.extension_proof veric.extspec.

Set Implicit Arguments.
Local Open Scope nat_scope.

Module CompCertModule. Section CompCertModule.
Variables F V C: Type.

Inductive Sig: Type := Make: forall
 (ge: Genv.t F V)
 (csem: CoreSemantics (Genv.t F V) C mem (list (ident * globdef F V))),
 Sig.

End CompCertModule. End CompCertModule.

Definition get_module_genv F V C (ccm: CompCertModule.Sig F V C): Genv.t F V :=
  match ccm with CompCertModule.Make g _ => g end.

Definition get_module_csem F V C (ccm: CompCertModule.Sig F V C) :=
  match ccm with CompCertModule.Make _ sem => sem end.

Inductive frame (cT: nat -> Type) (num_modules: nat): Type := mkFrame: 
 forall (i: nat) (PF: i < num_modules) (c: cT i), frame cT num_modules.
Implicit Arguments mkFrame [cT num_modules].

Definition call_stack (cT: nat -> Type) (num_modules: nat) := list (frame cT num_modules).

Section LinkerCoreSemantics.
Variables (F V: Type) (ge: Genv.t F V) (num_modules: nat).
Variables (cT fT vT: nat -> Type)
 (procedure_linkage_table: ident -> option nat)
 (plt_ok: 
   forall (id: ident) (i: nat), 
   procedure_linkage_table id = Some i -> i < num_modules)
 (modules: forall i: nat, i < num_modules -> CompCertModule.Sig (fT i) (vT i) (cT i))
 (entry_points: list (val*val*signature)).

Implicit Arguments plt_ok [].

Definition all_at_external (l: call_stack cT num_modules) :=
 List.Forall (fun f => match f with mkFrame i pf_i c => 
  exists ef, exists sig, exists args,
   at_external (get_module_csem (modules pf_i)) c = Some (ef, sig, args)
  end) l.

Inductive linker_corestate: Type := mkLinkerCoreState: forall
 (stack: call_stack cT num_modules)
 (stack_nonempty: length stack >= 1)
 (callers_at_external: all_at_external (List.tail stack)),
 linker_corestate.

Implicit Arguments mkLinkerCoreState [].

Definition genvs_agree (F1 F2 V1 V2: Type) (ge1: Genv.t F1 V1) (ge2: Genv.t F2 V2) :=
  (forall id: ident, Genv.find_symbol ge1 id=Genv.find_symbol ge2 id) /\
  (forall b v1 v2,
    ZMap.get b (Genv.genv_vars ge1) = Some v1 -> ZMap.get b (Genv.genv_vars ge2) = Some v2 ->  
    gvar_init v1=gvar_init v2).

Lemma length_cons {A: Type}: forall (a: A) (l: list A), length (a :: l) >= 1.
Proof. solve[intros; simpl; omega]. Qed.

Lemma all_at_external_consnil: forall f, all_at_external (List.tail (f::nil)).
Proof.
unfold all_at_external; intros; simpl.
solve[apply Forall_nil].
Qed.

Lemma all_at_external_cons: forall f l, all_at_external (f::l) -> all_at_external l.
Proof.
intros f l; revert f; destruct l; simpl; auto.
solve[intros f H1; constructor].
intros f' H1.
unfold all_at_external in H1.
inversion H1; subst; auto.
Qed.

Inductive linker_corestep: 
  Genv.t F V -> linker_corestate -> mem -> linker_corestate -> mem -> Prop :=
(** coresteps of the 'top' core *)                    
| link_step: forall ge (stack: call_stack cT num_modules) 
                    i c m (pf_i: i < num_modules) c' m' pf ext_pf,
  (forall (k: nat) (pf_k: k<num_modules), genvs_agree ge (get_module_genv (modules pf_k))) ->
  (forall (k: nat) (pf_k: k<num_modules), genvs_domain_eq ge (get_module_genv (modules pf_k))) ->
  corestep (get_module_csem (modules pf_i)) (get_module_genv (modules pf_i)) c m c' m' ->
  linker_corestep ge
   (mkLinkerCoreState (mkFrame i pf_i c :: stack) pf ext_pf) m
   (mkLinkerCoreState (mkFrame i pf_i c' :: stack) pf ext_pf) m'

(** 'link' steps *)
| link_call: forall ge stack i j args id sig b (c: cT i) m (pf_i: i < num_modules) c' 
   (LOOKUP: procedure_linkage_table id = Some j) 
   (NEQ_IJ: i<>j) (** 'external' functions cannot be defined within this module *)
   (AT_EXT: at_external (get_module_csem (modules pf_i)) c = 
     Some (EF_external id sig, sig, args)) pf ext_pf ext_pf',
  (forall (k: nat) (pf_k: k<num_modules), genvs_agree ge (get_module_genv (modules pf_k))) ->
  (forall (k: nat) (pf_k: k<num_modules), genvs_domain_eq ge (get_module_genv (modules pf_k))) ->
  Genv.find_symbol ge id = Some b -> 
  In (Vptr b (Int.repr 0), Vptr b (Int.repr 0), sig) entry_points -> 
  make_initial_core 
   (get_module_csem (modules (plt_ok id j LOOKUP)))
   (get_module_genv (modules (plt_ok id j LOOKUP))) (Vptr b (Int.repr 0)) args = Some c' -> 

  linker_corestep ge
   (mkLinkerCoreState (mkFrame i pf_i c :: stack) pf ext_pf) m
   (mkLinkerCoreState 
     (mkFrame j (plt_ok id j LOOKUP) c' :: mkFrame i pf_i c :: stack) (length_cons _ _) ext_pf') m

(** 'return' steps *)
| link_return: forall ge stack i j id c m (pf_i: i < num_modules) c' c'' retv
   (LOOKUP: procedure_linkage_table id = Some j)
   (HALTED: safely_halted (get_module_csem (modules (plt_ok id j LOOKUP))) c' = Some retv) 
   pf ext_pf ext_pf',
  (forall (k: nat) (pf_k: k<num_modules), genvs_agree ge (get_module_genv (modules pf_k))) ->
  (forall (k: nat) (pf_k: k<num_modules), genvs_domain_eq ge (get_module_genv (modules pf_k))) ->
  after_external (get_module_csem (modules pf_i)) (Some retv) c = Some c'' -> 
  linker_corestep ge
   (mkLinkerCoreState 
     (mkFrame j (plt_ok id j LOOKUP) c' :: mkFrame i pf_i c :: stack) pf ext_pf) m
   (mkLinkerCoreState (mkFrame i pf_i c'' :: stack) (length_cons _ _) ext_pf') m.

Definition linker_at_external (s: linker_corestate) := 
  match s with
  | mkLinkerCoreState nil _ _ => None
  | mkLinkerCoreState (mkFrame i pf_i c :: call_stack) _ _ =>
     match at_external (get_module_csem (modules pf_i)) c with
     | Some (EF_external id sig, ef_sig, args) => 
       match procedure_linkage_table id with 
       | None => Some (EF_external id sig, ef_sig, args)
       | Some module_id => None
       end
     | Some (ef, sig, args) => Some (ef, sig, args)
     | None => None
     end
  end.
Implicit Arguments linker_at_external [].

Definition linker_after_external (retv: option val) (s: linker_corestate) :=
  match s with
  | mkLinkerCoreState nil _ _ => None
  | mkLinkerCoreState (mkFrame i pf_i c :: call_stack) _ ext_pf =>
    match after_external (get_module_csem (modules pf_i)) retv c with
    | None => None
    | Some c' => Some (mkLinkerCoreState (mkFrame i pf_i c' :: call_stack) 
       (length_cons _ _) ext_pf)
    end
  end.

Definition linker_safely_halted (s: linker_corestate) :=
  match s with
  | mkLinkerCoreState nil _ _ => None
  | mkLinkerCoreState (mkFrame i pf_i c :: nil) _ _ =>
     safely_halted (get_module_csem (modules pf_i)) c
  | mkLinkerCoreState (mkFrame i pf_i c :: call_stack) _ _ => None
  end.

Definition main_id := 1%positive. (*hardcoded*)

Definition linker_initial_mem (ge: Genv.t F V) (m: mem) (init_data: list (ident * globdef F V)) := 
  Genv.alloc_globals ge Mem.empty init_data = Some m.

Definition linker_make_initial_core (ge: Genv.t F V) (f: val) (args: list val) :=
  match f, Genv.find_symbol ge main_id with
  | Vptr b ofs, Some b' => 
    if Z_eq_dec b b' then 
       (match procedure_linkage_table main_id as x 
          return (x = procedure_linkage_table main_id -> option linker_corestate) with
       | None => fun _ => None (** no module defines 'main' *)
       | Some i => fun pf => 
         match make_initial_core (get_module_csem (modules (@plt_ok main_id i (eq_sym pf)))) 
                 (get_module_genv (modules (@plt_ok main_id i (eq_sym pf)))) f args with
         | None => None
         | Some c => Some (mkLinkerCoreState (mkFrame i (plt_ok main_id i (eq_sym pf)) c :: nil) 
                             (length_cons _ _) (all_at_external_consnil _))
         end 
       end) (refl_equal _)
     else None
   | _, _ => None (** either no 'main' was defined or [f] is not a [Vptr] *)
   end.

Program Definition linker_core_semantics: 
  CoreSemantics (Genv.t F V) linker_corestate mem (list (ident * globdef F V)) :=
 Build_CoreSemantics _ _ _ _ 
  linker_initial_mem 
  linker_make_initial_core
  linker_at_external
  linker_after_external
  linker_safely_halted
  linker_corestep _ _ _ _.
Next Obligation.
inv H.
apply corestep_not_at_external in H2.
solve[simpl; rewrite H2; auto].
simpl; rewrite AT_EXT, LOOKUP; auto.
simpl.
destruct (at_external_halted_excl (get_module_csem (modules (plt_ok id j LOOKUP))) c')
 as [H3|H3].
solve[rewrite H3; auto].
solve[rewrite H3 in HALTED; congruence].
Qed.
Next Obligation.
inv H.
apply corestep_not_halted in H2.
simpl; destruct stack; auto.
destruct (at_external_halted_excl (get_module_csem (modules pf_i)) c) 
 as [H5|H5].
simpl; destruct stack; auto.
solve[rewrite AT_EXT in H5; congruence].
solve[simpl; destruct stack; auto].
solve[auto].
Qed.
Next Obligation.
destruct q; simpl.
destruct stack; auto.
destruct f; auto.
case_eq (at_external (get_module_csem (modules PF)) c); [intros [[ef sig] args]|intros].
destruct ef; auto.
intros.
destruct (procedure_linkage_table name).
solve[left; auto].
destruct stack; auto.
destruct (at_external_halted_excl (get_module_csem (modules PF)) c) 
 as [H3|H3].
solve[rewrite H in H3; congruence].
solve[right; auto].
intros H1; destruct (at_external_halted_excl (get_module_csem (modules PF)) c) 
 as [H3|H3].
solve[rewrite H1 in H3; congruence].
solve[destruct stack; auto].
intros H1; destruct (at_external_halted_excl (get_module_csem (modules PF)) c) 
 as [H3|H3].
solve[rewrite H1 in H3; congruence].
solve[destruct stack; auto].
intros H1; destruct (at_external_halted_excl (get_module_csem (modules PF)) c) 
 as [H3|H3].
solve[rewrite H1 in H3; congruence].
solve[destruct stack; auto].
intros H1; destruct (at_external_halted_excl (get_module_csem (modules PF)) c) 
 as [H3|H3].
solve[rewrite H1 in H3; congruence].
solve[destruct stack; auto].
intros H1; destruct (at_external_halted_excl (get_module_csem (modules PF)) c) 
 as [H3|H3].
solve[rewrite H1 in H3; congruence].
solve[destruct stack; auto].
intros H1; destruct (at_external_halted_excl (get_module_csem (modules PF)) c) 
 as [H3|H3].
solve[rewrite H1 in H3; congruence].
solve[destruct stack; auto].
intros H1; destruct (at_external_halted_excl (get_module_csem (modules PF)) c) 
 as [H3|H3].
solve[rewrite H1 in H3; congruence].
solve[destruct stack; auto].
intros H1; destruct (at_external_halted_excl (get_module_csem (modules PF)) c) 
 as [H3|H3].
solve[rewrite H1 in H3; congruence].
solve[destruct stack; auto].
intros H1; destruct (at_external_halted_excl (get_module_csem (modules PF)) c) 
 as [H3|H3].
solve[rewrite H1 in H3; congruence].
solve[destruct stack; auto].
intros H1; destruct (at_external_halted_excl (get_module_csem (modules PF)) c) 
 as [H3|H3].
solve[rewrite H1 in H3; congruence].
solve[destruct stack; auto].
solve[left; auto].
Qed.
Next Obligation.
destruct q; simpl in H|-*.
destruct stack; try solve[inversion H].
destruct f; try solve[inversion H].
case_eq (after_external (get_module_csem (modules PF)) retv c).
intros c' H2; rewrite H2 in H.
inv H; apply after_at_external_excl in H2.
simpl; rewrite H2; auto.
case_eq (after_external (get_module_csem (modules PF)) retv c).
solve[intros c' H2; rewrite H2 in H; intro; congruence].
intros H2 H3.
solve[rewrite H2 in H; congruence].
Qed.

End LinkerCoreSemantics.

Section LinkingExtension.
Variables (F V: Type).
Variables
 (Z: Type) (** external states *) (cT fT vT: nat -> Type)
 (num_modules: nat) (procedure_linkage_table: ident -> option nat)
 (plt_ok: 
   forall (id: ident) (i: nat), 
   procedure_linkage_table id = Some i -> i < num_modules)
 (modules: forall i: nat, i < num_modules -> 
   CompCertModule.Sig (fT i) (vT i) (cT i))
 (csig: ext_spec Z) (esig: ext_spec Z)
 (handled: list AST.external_function)
 (entry_points: list (val*val*signature)).

(** Consistency conditions on handled functions and the procedure linkage table *)

Variable plt_in_handled:
 forall i j (pf: i < num_modules) c sig sig2 args id,
 at_external (get_module_csem (modules pf)) c = Some (EF_external id sig, sig2, args) ->
 procedure_linkage_table id = Some j -> In (EF_external id sig) handled.

Implicit Arguments linker_at_external [num_modules cT].

Variable at_external_not_handled:
 forall ef sig args s,
 linker_at_external fT vT procedure_linkage_table modules s = Some (ef, sig, args) ->
 IN ef handled = false.

Variable linkable_csig_esig: linkable (fun z : Z => z) handled csig esig.

Definition genv_map: nat -> Type := fun i: nat => Genv.t (fT i) (vT i).

Program Definition trivial_core_semantics: forall i: nat, 
 CoreSemantics (genv_map i) (cT i) mem (list (ident * globdef (fT i) (vT i))) :=
 fun i: nat => Build_CoreSemantics _ _ _ _ 
  (fun _ _ _ => False) (fun _ _ _ => None) (fun _ => None) 
  (fun _ _ => None) (fun _ => None) (fun _ _ _ _ _ => False) _ _ _ _.

Definition csem_map: forall i: nat, 
 CoreSemantics (genv_map i) (cT i) mem (list (ident * globdef (fT i) (vT i))) :=
 fun i: nat => match lt_dec i num_modules with
               | left pf => get_module_csem (modules pf)
               | right _ => trivial_core_semantics i
               end.

Program Definition trivial_genv (i: nat): Genv.t (fT i) (vT i) :=
 Genv.mkgenv (PTree.empty block) (ZMap.init None) (ZMap.init None) (Zgt_pos_0 1) 
 _ _ _ _ _.
Next Obligation. solve[rewrite PTree.gempty in H; congruence]. Qed.
Next Obligation. solve[rewrite ZMap.gi in H; congruence]. Qed.
Next Obligation. solve[rewrite ZMap.gi in H; congruence]. Qed.
Next Obligation. solve[rewrite ZMap.gi in H; congruence]. Qed.
Next Obligation. solve[rewrite PTree.gempty in H; congruence]. Qed.

Definition genvs: forall i: nat, Genv.t (fT i) (vT i) :=
 fun i: nat => match lt_dec i num_modules with
               | left pf => get_module_genv (modules pf)
               | right _ => trivial_genv i
               end.

Import TruePropCoercion.

Definition init_data := fun i: nat => list (ident * globdef (fT i) (vT i)).

Implicit Arguments linker_corestate [fT vT].

Fixpoint find_core (i: nat) (l: call_stack cT num_modules) :=
 match l with
 | nil => None
 | mkFrame j pf_j c :: l' => 
    match eq_nat_dec i j with
    | left pf => Some (eq_rect j (fun x => cT x) c i (sym_eq pf))
    | right _ => find_core i l'
    end
 end.

Definition linker_proj_core (i: nat) (s: linker_corestate num_modules cT modules): option (cT i) :=
  match s with mkLinkerCoreState l _ _ => find_core i l end.
(*
  | mkLinkerCoreState (mkFrame j pf_j c :: call_stack) _ _ =>
     match eq_nat_dec i j with 
     | left pf => Some (eq_rect j (fun x => cT x) c i (sym_eq pf))
     | right _ => None
     end
  end.
*)

Definition linker_active (s: linker_corestate num_modules cT modules): nat :=
  match s with
  | mkLinkerCoreState nil _ _ => 0
  | mkLinkerCoreState (mkFrame i pf_i c :: call_stack) _ _ => i
  end.

Lemma dependent_types_nonsense: forall i (c: cT i) (e: i=i), 
 eq_rect i (fun x => cT x) c i (eq_sym e) = c.
Proof. Admitted.

Program Definition linking_extension: 
 @Extension.Sig (Genv.t F V) (list (ident * globdef F V)) 
     (linker_corestate num_modules cT modules) genv_map cT mem init_data Z unit Z
     (linker_core_semantics F V cT fT vT procedure_linkage_table plt_ok modules entry_points)
     csem_map csig esig handled :=
 Extension.Make genv_map (fun i: nat => list (ident * globdef (fT i) (vT i)))
  (linker_core_semantics F V cT fT vT procedure_linkage_table plt_ok modules entry_points)
  csem_map csig esig handled num_modules
  linker_proj_core _  
  linker_active _ 
  (fun _ => tt) (fun z: Z => z) (fun (_:unit) (z: Z) => z)
  _ _ _ _ _.
Next Obligation.
unfold linker_proj_core, find_core.
destruct s. revert H. induction stack; auto. destruct a; auto.
destruct (eq_nat_dec i i0); auto. subst.
intros.
solve[elimtype False; omega].
intros.
destruct stack; auto.
eapply IHstack; auto.
simpl; omega.
simpl; simpl in callers_at_external.
solve[inv callers_at_external; auto].
Qed.
Next Obligation.
unfold linker_proj_core, linker_active.
destruct s; simpl.
destruct stack; simpl.
solve[simpl in stack_nonempty; elimtype False; omega].
destruct f; simpl.
destruct (eq_nat_dec i i); try solve[elimtype False; auto].
exists c; f_equal.
unfold eq_rect, eq_sym.
Admitted. (*dependent types*)
Next Obligation.
unfold linker_proj_core in H.
destruct s.
revert H H1.
induction stack.
solve[simpl; intros; congruence].
simpl; destruct a; try solve[congruence].
destruct (eq_nat_dec i i); try solve[congruence].
intros H H1.
rewrite dependent_types_nonsense in H.
inversion H.
subst c.
case_eq (at_external (get_module_csem (modules PF)) c0); 
 try solve[congruence].
destruct p as [[ef' sig'] args'].
destruct ef'; try solve[congruence
 |intros H2; rewrite H2 in H1; try solve[congruence]].
case_eq (procedure_linkage_table name); try solve[congruence].
intros n H2 H3.
rewrite H3 in H1.
unfold csem_map in H0.
simpl in H0.
destruct (lt_dec i num_modules).
assert (PF = l) by apply proof_irr.
subst. unfold genv_map in H0. 
rewrite H0 in H3; inv H3.
solve[apply ListSet.set_mem_correct2; eapply plt_in_handled; eauto].
elimtype False; auto.
solve[intros H2 H3; rewrite H3, H2 in H1; congruence].
intros H2; rewrite H2 in H1.
unfold csem_map in H0.
simpl in H0.
destruct (lt_dec i num_modules); [|solve[elimtype False; auto]].
assert (PF = l) by apply proof_irr.
subst. unfold genv_map in H0. 
solve[rewrite H0 in H2; inv H2].
Qed.
Next Obligation. solve[eapply at_external_not_handled; eauto]. Qed.

Lemma linker_stepN s c m c' m' n ge 
 (genvs_agree: forall (k : nat) (pf_k : k < num_modules),
  genvs_agree ge (get_module_genv (modules pf_k)))
 (genvs_domain_eq: forall (k : nat) (pf_k : k < num_modules),
  genvs_domain_eq ge (get_module_genv (modules pf_k))) :
 linker_proj_core (linker_active s) s = Some c -> 
 corestepN (csem_map (linker_active s)) (genvs (linker_active s)) n c m c' m' ->
 exists s', corestepN 
  (linker_core_semantics F V cT fT vT procedure_linkage_table plt_ok modules entry_points) 
  ge n s m s' m' /\ linker_active s=linker_active s /\
  linker_proj_core (linker_active s) s' = Some c'.
Proof.
revert s c m c' m'.
induction n; simpl.
intros s c m c' m' H1 H2; inv H2.
solve[exists s; split; auto].
intros s c m c' m' H1 [c2 [m2 [STEP12 STEP23]]].
destruct s; simpl in *.
unfold find_core in *.
destruct stack; try solve[congruence].
destruct f.
specialize (IHn 
 (mkLinkerCoreState (mkFrame i PF c2 :: stack) stack_nonempty callers_at_external)
 c2 m2 c' m'
).
simpl in IHn; spec IHn.
destruct (eq_nat_dec i i); try solve[elimtype False; omega].
solve[rewrite dependent_types_nonsense; auto].
destruct IHn as [s' [STEP23' [_ PROJ]]]; auto.
destruct (eq_nat_dec i i); try solve[elimtype False; omega].
rewrite dependent_types_nonsense in H1.
inversion H1; rewrite H0 in *; clear H0 H1.
exists s'; split; auto.
exists (mkLinkerCoreState (mkFrame i PF c2 :: stack) stack_nonempty callers_at_external).
exists m2.
split; auto.
constructor; auto.
unfold csem_map, genvs in STEP12.
destruct (lt_dec i num_modules); try solve[elimtype False; omega].
solve[assert (PF=l) as -> by apply proof_irr; auto].
Qed.

Lemma linker_core_compatible: forall (ge: Genv.t F V) 
   (agree: forall (k : nat) (pf_k : k < num_modules),
   genvs_agree ge (get_module_genv (modules pf_k)))
   (domain_eq: forall (k : nat) (pf_k : k < num_modules),
     genvs_domain_eq ge (get_module_genv (modules pf_k)))
   (csem_fun: forall i: nat, corestep_fun (csem_map i)),
 @core_compatible (Genv.t F V) (linker_corestate num_modules cT modules) mem 
        (list (ident*globdef F V)) Z unit Z
        (fun i => Genv.t (fT i) (vT i)) cT init_data 
        (linker_core_semantics F V cT fT vT procedure_linkage_table plt_ok modules entry_points) 
        csem_map csig esig handled 
 ge genvs linking_extension.
Proof.
intros; constructor.

intros until c; simpl; intros H1 H2 H3.
inv H3; simpl in H2|-*.
destruct (eq_nat_dec i i); try solve[elimtype False; auto].
inv H2.
simpl in H1.
exists c'.
unfold csem_map, genvs.
destruct (lt_dec i num_modules); try solve[elimtype False; omega].
split.
assert (l = pf_i) by apply proof_irr.
rewrite H2.
solve[rewrite dependent_types_nonsense; auto].
solve[rewrite dependent_types_nonsense; auto].
unfold runnable, csem_map in H1.
simpl in H1.
destruct (lt_dec i num_modules); try solve[elimtype False; omega].
destruct (eq_nat_dec i i); try solve[elimtype False; auto].
inv H2.
rewrite dependent_types_nonsense in H1.
assert (H2: l = pf_i) by apply proof_irr. 
rewrite H2 in H1.
solve[unfold init_data in H1; rewrite AT_EXT in H1; congruence].
destruct (eq_nat_dec j j); try solve[elimtype False; omega].
rewrite dependent_types_nonsense in H2.
inversion H2. 
rewrite H5 in *; clear H5 H2 e.
unfold runnable in H1; simpl in H1.
unfold init_data in H1.
destruct (@at_external (Genv.t (fT j) (vT j)) (cT j) Mem.mem
             (list (prod ident (globdef (fT j) (vT j)))) 
             (csem_map j) c).
congruence.
unfold csem_map in H1.
generalize LOOKUP as LOOKUP'; intro.
apply plt_ok in LOOKUP'.
destruct (lt_dec j num_modules); try solve[elimtype False; omega].
assert (H2: l = plt_ok LOOKUP) by apply proof_irr.
rewrite H2 in H1.
rewrite HALTED in H1.
congruence.

intros until m'; simpl; intros H1 H2 H3.
inv H3; simpl in *.
assert (Heq: c0 = c). 
 destruct (eq_nat_dec i i); try solve[elimtype False; omega].
 solve[rewrite dependent_types_nonsense in H1; inv H1; auto].
subst c0.
clear H1.
split; auto.
destruct (eq_nat_dec i i); try solve[elimtype False; omega].
rewrite dependent_types_nonsense.
generalize (csem_fun i).
unfold csem_map, genvs in H2|-*.
destruct (lt_dec i num_modules); try solve[elimtype False; omega].
assert (H3: l = pf_i) by apply proof_irr.
rewrite H3 in H2|-*.
clear H3 e.
intros csem_fun'.
f_equal.
eapply csem_fun' in H2.
spec H2; eauto.
inv H2; auto.
assert (Heq: c0 = c). 
 destruct (eq_nat_dec i i); try solve[elimtype False; omega].
 solve[rewrite dependent_types_nonsense in H1; inv H1; auto].
subst c0.
clear H1.
unfold csem_map in H2.
destruct (lt_dec i num_modules); try solve[elimtype False; omega].
apply corestep_not_at_external in H2.
assert (H3: l = pf_i) by apply proof_irr.
rewrite H3 in H2; clear H3.
unfold init_data in *; rewrite H2 in AT_EXT.
congruence.
assert (Heq: c'0 = c). 
 destruct (eq_nat_dec j j); try solve[elimtype False; omega].
 solve[rewrite dependent_types_nonsense in H1; inv H1; auto].
subst c'0.
clear H1.
unfold csem_map in H2.
generalize LOOKUP as LOOKUP'; intro.
apply plt_ok in LOOKUP'.
destruct (lt_dec j num_modules); try solve[elimtype False; omega].
apply corestep_not_halted in H2.
assert (H3: l = plt_ok LOOKUP) by apply proof_irr.
rewrite H3 in H2; clear H3.
unfold init_data in *; rewrite H2 in HALTED.
congruence.

intros until m'; intros H1 H2.
simpl in *.
destruct s.
destruct stack; simpl in *.
congruence.
destruct f.
destruct (eq_nat_dec i i); try solve[congruence].
rewrite dependent_types_nonsense in H1.
inv H1.
clear e.
exists (mkLinkerCoreState (mkFrame i PF c' :: stack) stack_nonempty callers_at_external).
constructor; auto.
unfold csem_map, genvs in H2.
destruct (lt_dec i num_modules); try solve[elimtype False; omega].
assert (H3: l = PF) by apply proof_irr.
rewrite H3 in H2.
solve[apply H2].

intros until m'; intros H1 H2 H3 H4 j H5.
inv H4; simpl in *.
destruct (eq_nat_dec i i); try solve[elimtype False; omega|auto].
destruct (eq_nat_dec j i); try solve[elimtype False; omega|auto].
subst; destruct (eq_nat_dec j j0); try solve[elimtype False; omega].
subst; destruct (eq_nat_dec j i); try solve[elimtype False; omega].
solve[auto].

intros until n; intros H1 H2 H3 j H4.
admit. (*tedious*)

intros until retv; intros H1 H2 H3.
destruct s; destruct s'; simpl in H3.
destruct stack; try solve[inv H3].
destruct f.
unfold csem_map in H2; simpl in H2.
destruct (lt_dec i num_modules); try solve[elimtype False; congruence].
assert (H4: l = PF) by apply proof_irr; auto.
rewrite H4 in H2.
unfold init_data in *.
assert (H: c0 = c).
 simpl in H1.
 destruct (eq_nat_dec i i); try solve[elimtype False; omega].
 rewrite dependent_types_nonsense in H1.
 solve[inversion H1; auto].
rewrite H in *.
rewrite H2 in H3.
inversion H3.
solve[subst stack0; auto].

intros until retv; intros H1 H2.
destruct s; simpl in *.
unfold find_core in *.
destruct stack; try solve[congruence].
destruct f.
destruct (eq_nat_dec i i); try solve[elimtype False; omega].
rewrite dependent_types_nonsense in H1.
inv H1.
clear e.
exists (mkLinkerCoreState (mkFrame i PF c' :: stack) stack_nonempty callers_at_external).
unfold csem_map in H2.
destruct (lt_dec i num_modules); try solve[elimtype False; omega].
assert (H: l = PF) by apply proof_irr; auto.
rewrite H in H2.
unfold init_data in *; rewrite H2.
simpl.
destruct (eq_nat_dec i i); try solve[elimtype False; omega].
split; auto.
repeat f_equal; auto.
solve[rewrite dependent_types_nonsense; auto].

intros until retv; intros H1 j H2.
destruct s; destruct s'; simpl in *.
destruct stack; try solve[inv H1].
destruct f.
destruct (eq_nat_dec j i); try solve[elimtype False; omega].
destruct (after_external (get_module_csem (modules PF)) retv c).
inv H1.
simpl.
destruct (eq_nat_dec j i); try solve[elimtype False; omega].
auto.
congruence.

intros until args; intros H1.
destruct s; simpl in *|-.
destruct stack; try solve[congruence].
destruct f.
exists c; simpl.
destruct (eq_nat_dec i i); try solve[elimtype False; omega].
split.
rewrite dependent_types_nonsense; auto.
unfold csem_map.
destruct (lt_dec i num_modules); try solve[elimtype False; omega].
assert (l = PF) as -> by apply proof_irr; auto.
unfold init_data.
destruct (at_external (get_module_csem (modules PF)) c).
destruct p as [[ef' sig'] args'].
destruct ef'; auto.
destruct (procedure_linkage_table name); try solve[congruence].
congruence.
Qed.

End LinkingExtension.

Section LinkerCompilable.
Variables 
 (F_S F_T V_S V_T: Type) 
 (geS: Genv.t F_S V_S) (geT: Genv.t F_T V_T) (num_modules: nat).
Variables 
 (cS cT fS fT vS vT: nat -> Type)
 (procedure_linkage_table: ident -> option nat)
 (plt_ok: 
   forall (id: ident) (i: nat), 
   procedure_linkage_table id = Some i -> i < num_modules)
 (modules_S: forall i: nat, i < num_modules -> CompCertModule.Sig (fS i) (vS i) (cS i))
 (modules_T: forall i: nat, i < num_modules -> CompCertModule.Sig (fT i) (vT i) (cT i)).

Variables (csig: ext_spec Z) (esig: ext_spec Z) 
 (handled: list AST.external_function).

(** Conditions required to construct a linking extension *)

Variable linkable_csig_esig: linkable (fun z : Z => z) handled csig esig.

Variable plt_in_handled_S:
 forall i j (pf: i < num_modules) c sig sig2 args id,
 at_external (get_module_csem (modules_S pf)) c = Some (EF_external id sig, sig2, args) ->
 procedure_linkage_table id = Some j -> In (EF_external id sig) handled.
Variable plt_in_handled_T:
 forall i j (pf: i < num_modules) c sig sig2 args id,
 at_external (get_module_csem (modules_T pf)) c = Some (EF_external id sig, sig2, args) ->
 procedure_linkage_table id = Some j -> In (EF_external id sig) handled.

Implicit Arguments linker_at_external [num_modules cT].

Variable at_external_not_handled_S:
 forall ef sig args s,
 linker_at_external fS vS procedure_linkage_table modules_S s = Some (ef, sig, args) ->
 IN ef handled = false.
Variable at_external_not_handled_T:
 forall ef sig args s,
 linker_at_external fT vT procedure_linkage_table modules_T s = Some (ef, sig, args) ->
 IN ef handled = false.

(** Begin compilability proof *)

Definition csem_map_S := csem_map cS fS vS modules_S.
Definition csem_map_T := csem_map cT fT vT modules_T.

Variable agree_S: forall (k : nat) (pf_k : k < num_modules),
 genvs_agree geS (get_module_genv (modules_S pf_k)).
Variable agree_T: forall (k : nat) (pf_k : k < num_modules),
 genvs_agree geT (get_module_genv (modules_T pf_k)). 
Variable agree_ST: forall (k : nat) (pf_k : k < num_modules),
 genvs_agree (get_module_genv (modules_S pf_k)) (get_module_genv (modules_T pf_k)).

Definition genv_mapS := genvs cS fS vS modules_S. 
Definition genv_mapT := genvs cT fT vT modules_T. 

Variable domain_eq: genvs_domain_eq geS geT.
Variable domain_eq_S: forall (i: nat), genvs_domain_eq geS (genv_mapS i).
Variable domain_eq_T: forall (i: nat), genvs_domain_eq geT (genv_mapT i).

Variable csem_fun_S: forall i: nat, corestep_fun (csem_map_S i).
Variable csem_fun_T: forall i: nat, corestep_fun (csem_map_T i).

Import ExtensionCompilability.
Import Sim_inj_exposed.

Variable core_data: nat -> Type.
Variable match_state: forall i: nat,
 core_data i ->  meminj -> cS i -> mem -> cT i -> mem -> Prop.
Variable core_ord: forall i: nat, core_data i -> core_data i -> Prop.
Variable threads_max: nat. 
Variable threads_max_nonzero: (O < threads_max)%nat. (*Required by defn. of core_ords*)

Variable RGsim: forall i: nat,
 RelyGuaranteeSimulation.Sig (csem_map_S i) (csem_map_T i) (genv_mapS i) (@match_state i).

Variable entry_points: list (val*val*signature).

Variable core_simulations: forall i: nat,
 Forward_simulation_inject
  (list (ident * globdef (fS i) (vS i)))
  (list (ident * globdef (fT i) (vT i))) (csem_map_S i) 
  (csem_map_T i) (genv_mapS i) (genv_mapT i) entry_points 
  (core_data i) (@match_state i) (@core_ord i).

Implicit Arguments linker_corestate [fT vT].

Definition R_inv (_:meminj) (x:linker_corestate num_modules cS modules_S) (_:mem) 
                            (y:linker_corestate num_modules cT modules_T) (_:mem) := 
 match x, y with
 | mkLinkerCoreState stack1 _ _, mkLinkerCoreState stack2 _ _ => 
    length stack1=length stack2
 end.

Lemma linking_extension_compilable:
 CompilableExtension.Sig 
 (@linker_core_semantics F_S V_S num_modules cS fS vS 
   procedure_linkage_table plt_ok modules_S entry_points)
 (@linker_core_semantics F_T V_T num_modules cT fT vT 
   procedure_linkage_table plt_ok modules_T entry_points)
 geS geT entry_points.
Proof.
set (R := R_inv).
destruct (@ExtensionCompilability 
 _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
 (@linker_core_semantics F_S V_S num_modules cS fS vS 
   procedure_linkage_table plt_ok modules_S entry_points)
 (@linker_core_semantics F_T V_T num_modules cT fT vT 
   procedure_linkage_table plt_ok modules_T entry_points)
 csem_map_S csem_map_T csig esig handled 
 geS geT genv_mapS genv_mapT 
 (@linking_extension F_S V_S Z cS fS vS 
   num_modules procedure_linkage_table plt_ok modules_S csig esig 
   handled entry_points 
   plt_in_handled_S at_external_not_handled_S linkable_csig_esig)
 (@linking_extension F_T V_T Z cT fT vT 
   num_modules procedure_linkage_table plt_ok modules_T csig esig 
   handled entry_points 
   plt_in_handled_T at_external_not_handled_T linkable_csig_esig)
 entry_points core_data match_state core_ord threads_max R)
 as [LEM].
apply LEM; auto.
apply linker_core_compatible; auto. 
 clear - domain_eq_S.
 unfold genv_mapS, genvs in domain_eq_S.
 intros k pf_k.
 specialize (domain_eq_S k).
 destruct (lt_dec k num_modules); try solve[elimtype False; omega].
 solve[assert (pf_k = l) as -> by apply proof_irr; auto]. 
apply linker_core_compatible; auto. 
 clear - domain_eq_T.
 unfold genv_mapT, genvs in domain_eq_T.
 intros k pf_k.
 specialize (domain_eq_T k).
 destruct (lt_dec k num_modules); try solve[elimtype False; omega].
 solve[assert (pf_k = l) as -> by apply proof_irr; auto].
clear LEM; constructor; simpl.

(*1*)
admit. (*TODO*)

(*2*)
admit. (*TODO*)

(*3: extension_diagram*)
unfold CompilabilityInvariant.match_states; simpl. 
intros until j; intros H1 H2 H3 H4 H5 H6; intros [RR [H7 H8]] H9 H10 H11 H12 STEP.
inv STEP; simpl in *; subst.
(*'run' case*)
elimtype False.
clear - H1 H5 H13 pf_i.
unfold csem_map_S in H5.
apply corestep_not_at_external in H13.
unfold csem_map in H5.
destruct (lt_dec (linker_active s2) num_modules); try solve[omega].
destruct (eq_nat_dec (linker_active s2) (linker_active s2)); try solve[omega].
rewrite dependent_types_nonsense in H1; inv H1.
assert (Heq: l = pf_i) by apply proof_irr; auto.
solve[subst; unfold init_data in *; rewrite H5 in H13; congruence].

(*'link' case*)
destruct (eq_nat_dec (linker_active s2) (linker_active s2)); try solve[omega].
rewrite dependent_types_nonsense in H1; inv H1.
rename j0 into k.
destruct (core_simulations k).
specialize (core_initial0 (Vptr b (Int.repr 0)) (Vptr b (Int.repr 0)) sig).
spec core_initial0; auto.
assert (sig = sig0) as ->.
 clear - H5 AT_EXT.
 unfold csem_map_S, csem_map in H5.
 destruct (lt_dec (linker_active s2) num_modules); try solve[elimtype False; omega].
 assert (Heq: l = pf_i) by apply proof_irr; auto; subst.
 solve[rewrite H5 in AT_EXT; inv AT_EXT; auto].
solve[auto].
specialize (core_initial0 args1 c' m1' j args2 m2).
spec core_initial0; auto.
clear - H5 AT_EXT H15.
unfold csem_map_S, csem_map in H5.
destruct (lt_dec (linker_active s2) num_modules); try solve[elimtype False; omega].
assert (Heq: l = pf_i) by apply proof_irr; auto.
subst; rewrite H5 in AT_EXT; inv AT_EXT.
unfold csem_map_S, csem_map, genv_mapS, genvs.
generalize (plt_ok LOOKUP) as plt_ok'; intro.
destruct (lt_dec k num_modules); try solve[elimtype False; omega].
assert (Heq: l = plt_ok LOOKUP) by apply proof_irr; auto.
solve[subst; auto].
spec core_initial0; auto.
spec core_initial0; auto.
spec core_initial0; auto.
destruct core_initial0 as [cd' [c'' [INIT MATCH]]].
destruct s2; simpl in H2; induction stack0.
solve[simpl in stack_nonempty; elimtype False; omega].
destruct a.
unfold find_core in H2.
destruct (eq_nat_dec i i); try solve[elimtype False; omega].
rewrite dependent_types_nonsense in H2.
inversion H2; rewrite H7 in *; clear H7.
simpl in *.
assert (CALLERS: 
 all_at_external fT vT modules_T (List.tail (mkFrame k (plt_ok LOOKUP) c'' :: 
  mkFrame i pf_i c2 :: stack0))).
 simpl.
 apply List.Forall_cons.
 exists ef; exists sig; exists args2.
 generalize H6.
 unfold csem_map_T, csem_map.
 destruct (lt_dec i num_modules); try solve[elimtype False; omega].
 solve[assert (l = pf_i) as -> by apply proof_irr; auto].
 solve[apply callers_at_external].
exists (mkLinkerCoreState (mkFrame k (plt_ok LOOKUP) c'' :: 
  mkFrame i pf_i c2 :: stack0) (length_cons _ _) CALLERS).
exists m2.
exists (@ExtendedSimulations.core_datas_upd _ k cd' cd).
exists j.
split; auto.
split; auto.
solve[apply inject_separated_same_meminj].
split.
split.
inv RR.
rewrite H7 in *.
solve[simpl; auto].
split.
solve[simpl; auto].
intros.
simpl.
destruct (eq_nat_dec i0 k).
subst.
rewrite dependent_types_nonsense in H1.
inv H1.
exists c''.
split; auto.
solve[rewrite ExtendedSimulations.core_datas_upd_same; auto].

(*'callers' subcase*)
specialize (H8 i0 c0).
generalize H8.
destruct (eq_nat_dec i0 i); try solve[congruence].
subst i0.
intros H8'.
exists c2.
split.
solve[rewrite dependent_types_nonsense; auto].
rewrite ExtendedSimulations.core_datas_upd_other; auto.
spec H8'; auto.
destruct H8' as [c3 [H8' H8'']].
rewrite dependent_types_nonsense in H8'.
inv H8'.
solve[auto].
intros H16.
spec H16; auto.
destruct H16 as [c3 [H16 H16']].
exists c3.
split; auto.
solve[rewrite ExtendedSimulations.core_datas_upd_other; auto].

left.
exists O; simpl.
exists (mkLinkerCoreState 
 (mkFrame k (plt_ok LOOKUP) c'' :: mkFrame i pf_i c2 :: stack0) (length_cons _ _) CALLERS).
exists m2.
split; auto.
assert (Heq: pf_i = PF) by apply proof_irr; auto.
subst pf_i.
apply link_call 
 with (args := args2) (sig := sig) (b := b); auto.
specialize (H8 i c1).
spec H8.
destruct (eq_nat_dec i i); try solve[elimtype False; omega].
solve[rewrite dependent_types_nonsense; auto].
destruct H8 as [c2' H8].
destruct (eq_nat_dec i i); try solve[elimtype False; omega].
rewrite dependent_types_nonsense in H8.
destruct H8 as [H8 H16].
inv H8.
unfold csem_map_T, csem_map in H6.
destruct (lt_dec i num_modules); try solve[elimtype False; omega].
assert (l = PF) as -> by apply proof_irr; auto.
clear - H5 AT_EXT H6. 
unfold csem_map_S, csem_map in H5.
destruct (lt_dec i num_modules); try solve[elimtype False; omega].
assert (l = PF) by apply proof_irr; auto; subst.
solve[rewrite H5 in AT_EXT; inv AT_EXT; auto].
clear - domain_eq_T.
unfold genv_mapT, genvs in domain_eq_T.
intros k pf_k.
specialize (domain_eq_T k).
destruct (lt_dec k num_modules); try solve[elimtype False; omega].
solve[assert (pf_k = l) as -> by apply proof_irr; auto].
clear - agree_S agree_ST agree_T H13 LOOKUP plt_ok.
unfold genvs_agree in agree_S, agree_ST, agree_T.
destruct (agree_S (plt_ok LOOKUP)) as [H1 _].
destruct (agree_ST (plt_ok LOOKUP)) as [H2 _].
destruct (agree_T (plt_ok LOOKUP)) as [H3 _].
specialize (H1 id).
rewrite H1 in H13.
specialize (H2 id).
rewrite H13 in H2.
specialize (H3 id).
solve[rewrite <-H2 in H3; auto].
assert (sig = sig0) as ->.
 clear - H5 AT_EXT.
 unfold csem_map_S, csem_map in H5.
 destruct (lt_dec i num_modules); try solve[elimtype False; omega].
 assert (Heq: l = PF) by apply proof_irr; auto; subst.
 solve[rewrite H5 in AT_EXT; inv AT_EXT; auto].
solve[auto].
unfold csem_map_T, csem_map, genv_mapT, genvs in INIT.
generalize (plt_ok LOOKUP) as plt_ok'; intro.
destruct (lt_dec k num_modules); try solve[elimtype False; omega].
solve[assert (plt_ok' = l) as -> by apply proof_irr; auto].
congruence. 

(*'return' case*)
destruct (eq_nat_dec (linker_active s2) (linker_active s2)); try solve[omega].
inv H1.
rewrite dependent_types_nonsense in H3, H5.
edestruct (@at_external_halted_excl 
 (Genv.t (fS (linker_active s2)) (vS (linker_active s2)))
 (cS (linker_active s2)) mem 
 (list (ident * globdef (fS (linker_active s2)) (vS (linker_active s2)))) 
 (csem_map_S (linker_active s2)) c').
congruence.
elimtype False; clear - HALTED LOOKUP H1 plt_ok.
generalize (plt_ok LOOKUP) as plt_ok'; intro.
unfold csem_map_S, csem_map in H1.
destruct (lt_dec (linker_active s2) num_modules); try solve[omega].
assert (Heq: l = plt_ok LOOKUP) by apply proof_irr; auto.
solve[subst; congruence].
congruence.

(*4: at_external_match*)
intros until j; intros H1 H2 H3 H4 H5 H6 H7 H8 H9 H10 H11 H12.
destruct s1; destruct s2; simpl in *.
unfold find_core in *.
destruct stack; try solve[congruence].
destruct stack0; try solve[congruence].
destruct f; destruct f0.
unfold csem_map_S, csem_map_T, csem_map in *.
destruct (lt_dec i num_modules); try solve[elimtype False; omega].
assert (l = PF) by apply proof_irr; auto; subst.
destruct (eq_nat_dec i0 i0); try solve[elimtype False; omega].
rewrite dependent_types_nonsense in H2, H3.
inv H2; inv H3.
rewrite H6 in H5.
assert (PF = PF0) as -> by apply proof_irr; auto.
rewrite H12.
destruct ef; auto.
solve[destruct (procedure_linkage_table name); try solve[congruence]].

(*5: make_initial_core_diagram*)
intros until sig; intros H1 H2 H3 H4 H5.
destruct s1; simpl in H2.
unfold linker_make_initial_core in H2.
case_eq v1.
solve[intros V; rewrite V in *; try solve[congruence]].
intros i V.
rewrite V in H2.
destruct v1; try solve[congruence].
intros f V.
rewrite V in H2.
congruence.
intros b i V.
rewrite V in H2.
case_eq (Genv.find_symbol geS main_id).
2: solve[intros H6; rewrite H6 in H2; destruct v1; congruence].
intros b' H6.
rewrite H6 in H2.
if_tac in H2; try solve[congruence].
(*revert H2.*)
case_eq (procedure_linkage_table main_id); try solve[congruence].
intros n PLT.
case_eq
 (make_initial_core (get_module_csem (modules_S (plt_ok PLT)))
   (get_module_genv (modules_S (plt_ok PLT))) 
   (Vptr b i) vals1); try solve[congruence].
intros c Heq; inv Heq.
destruct (core_simulations n).
specialize (core_initial0 (Vptr b' i) v2 sig H1 vals1 c m1 j vals2 m2).
spec core_initial0; auto.
unfold csem_map_S, csem_map, genv_mapS, genvs.
generalize (plt_ok PLT); intro.
destruct (lt_dec n num_modules); try solve[elimtype False; omega].
solve[assert (l = plt_ok PLT) as -> by apply proof_irr; auto].
spec core_initial0; auto.
spec core_initial0; auto.
spec core_initial0; auto.
destruct core_initial0 as [cd' [c2 [INIT MATCH]]].
assert (exists cd: CompilabilityInvariant.core_datas core_data, True) as [cd _].
 admit. (*need to know cd exists for each core*)
exists (ExtendedSimulations.core_datas_upd _ n cd' cd).
exists (mkLinkerCoreState (mkFrame n (plt_ok PLT) c2 :: nil) (length_cons _ _)
 (all_at_external_consnil _ _ _ _)).
simpl; split; auto.
unfold linker_make_initial_core.
case_eq v2.
admit. (*v2: bad case*)
admit. (*v2: bad case*)
admit. (*v2: bad case*)
intros b ofs V.
rewrite V in *.
assert (Genv.find_symbol geT main_id = Some b) as ->.
 admit. (*follows from genvs_agree facts*)
if_tac; try solve[elimtype False; omega].
generalize (refl_equal (procedure_linkage_table main_id)).
generalize PLT.
pattern (procedure_linkage_table main_id) at 0 2 4.
rewrite PLT in *.
intros ? ?.
unfold csem_map_T, csem_map, genv_mapT, genvs in INIT.
generalize (plt_ok PLT); intro.
destruct (lt_dec n num_modules); try solve[elimtype False; omega].
assert (plt_ok (eq_sym e) = l) as -> by apply proof_irr; auto.
unfold genv_map in INIT.
rewrite INIT.
assert (l = plt_ok PLT0) as -> by apply proof_irr; auto.
split.
simpl.
revert H2.
generalize (refl_equal (procedure_linkage_table main_id)).
generalize PLT.
pattern (procedure_linkage_table main_id) at 0 2 4.
rewrite PLT in *.
intros _ e.
destruct (make_initial_core
           (get_module_csem (modules_S (plt_ok (eq_sym e))))
           (get_module_genv (modules_S (plt_ok (eq_sym e)))) 
           (Vptr b' i) vals1); try solve[congruence].
intros H2.
inv H2.
solve[simpl; auto].
simpl; split; auto.
destruct stack.
simpl in stack_nonempty; elimtype False; omega.
destruct f; auto.
revert H2.
generalize (refl_equal (procedure_linkage_table main_id)).
generalize PLT.
pattern (procedure_linkage_table main_id) at 0 2 4.
rewrite PLT in *.
intros _ e.
destruct (make_initial_core
           (get_module_csem (modules_S (plt_ok (eq_sym e))))
           (get_module_genv (modules_S (plt_ok (eq_sym e)))) 
           (Vptr b' i) vals1); try solve[congruence].
revert H2.
generalize (refl_equal (procedure_linkage_table main_id)).
generalize PLT.
pattern (procedure_linkage_table main_id) at 0 2 4.
rewrite PLT in *.
intros _ e H2.
generalize H7.
assert (plt_ok PLT = plt_ok (eq_sym e)) as -> by apply proof_irr; auto.
intros H7'; rewrite H7' in H2.
inv H2.
simpl.
intros i0 c1.
destruct (eq_nat_dec i0 n); try solve[intros; congruence].
intros H16.
subst i0.
rewrite dependent_types_nonsense in H16.
inv H16.
exists c2.
split; auto.
solve[rewrite ExtendedSimulations.core_datas_upd_same; auto].

intros.
revert H2.
generalize (refl_equal (procedure_linkage_table main_id)).
generalize PLT.
pattern (procedure_linkage_table main_id) at 0 2 4.
rewrite PLT.
intros _ e.
assert (plt_ok (eq_sym e) = plt_ok PLT) as -> by apply proof_irr; auto.
solve[rewrite H0; intros; congruence].
intros PLT.
revert H2.
generalize (refl_equal (procedure_linkage_table main_id)).
generalize PLT.
pattern (procedure_linkage_table main_id) at 0 2 4.
rewrite PLT.
solve[intros; congruence].

(*6: safely_halted_step*)
intros until v1.
intros H1 H2.
unfold linker_safely_halted in H2.
destruct c1; try solve[congruence].
case_eq stack.
intros Hstack; rewrite Hstack in *; congruence.
intros f stack' Hstack.
rewrite Hstack in *.
destruct f.
case_eq stack'.
intros Hstack'; rewrite Hstack' in H2.
2: solve[intros ? ? Hstack'; rewrite Hstack' in H2; congruence].
destruct (core_simulations i).
unfold CompilabilityInvariant.match_states in H1.
destruct H1 as [RR [H1 H3]].
simpl in *. 
specialize (H3 (linker_active c2)).
rewrite Hstack in H1, H3.
unfold find_core in *.
subst i.
destruct (eq_nat_dec (linker_active c2) (linker_active c2)); try solve[elimtype False; omega].
specialize (H3 c).
rewrite dependent_types_nonsense in H3.
spec H3; auto.
destruct H3 as [c3 [H3 H4]].
generalize core_halted0; intro core_halted1.
specialize (core_halted1 (cd (linker_active c2)) j c m1 c3 m2 v1 H4).
spec core_halted1; auto.
generalize H2.
unfold csem_map_S, csem_map.
destruct (lt_dec (linker_active c2) num_modules); try solve[elimtype False; omega].
solve[assert (PF = l) as -> by apply proof_irr; auto].
destruct core_halted1 as [v2 [H5 [H6 H7]]].
exists v2.
split; auto.
split; auto.
unfold linker_safely_halted.
destruct c2.
destruct stack0.
simpl in stack_nonempty0; elimtype False; omega.
destruct f.
simpl in H6.
unfold csem_map_T, csem_map in H6.
destruct (lt_dec i num_modules); try solve[elimtype False; omega].
assert (PF0 = l) as -> by apply proof_irr; auto.
simpl in H3.
destruct (eq_nat_dec i i); try solve[elimtype False; omega].
rewrite dependent_types_nonsense in H3.
inversion H3.
subst c3.
destruct stack0; auto.
generalize RR.
rewrite Hstack.
simpl.
rewrite Hstack'.
simpl.
solve[intros H10; inversion H10].

(*7: safely_halted_diagram*)
intros until c2; intros H1 H2 H3 H4 H5.
split.
destruct (core_simulations (linker_active s1)).
generalize core_halted0.
intro core_halted1.
specialize (core_halted1 (cd (linker_active s1)) j c1 m1 c2 m2 rv).
spec core_halted1; auto.
destruct H1 as [RR [H6 H7]].
simpl in *.
destruct (H7 (linker_active s1) c1 H2) as [c1' [H8 H9]].
rewrite H3 in H8.
solve[inv H8; auto].
spec core_halted1; auto.
destruct core_halted1 as [v2 [INJ [HALT INJ']]].
admit. (*need to generalize safely_halted_diagram to injected rv'*)
inv H5.
elimtype False; clear - H2 H4 H6.
apply corestep_not_halted in H6.
generalize H4; unfold csem_map_S, csem_map; simpl.
destruct (lt_dec i num_modules); try solve[elimtype False; omega].
assert (l = pf_i) as -> by apply proof_irr; auto.
simpl in H2.
destruct (eq_nat_dec i i); try solve[elimtype False; omega].
rewrite dependent_types_nonsense in H2; inversion H2; subst c1.
solve[rewrite H6; intros; congruence].
simpl in H2.
destruct (eq_nat_dec i i); try solve[elimtype False; omega].
rewrite dependent_types_nonsense in H2; inversion H2; subst c1.
simpl in H4.
unfold csem_map_S, csem_map in H4.
destruct (lt_dec i num_modules); try solve[elimtype False; omega].
generalize @at_external_halted_excl; intros H5.
specialize (H5 _ _ _ _ (get_module_csem (modules_S l)) c).
rewrite H4 in H5.
assert (Heq: l = pf_i) by apply proof_irr; auto.
rewrite Heq in *.
rewrite AT_EXT in H5.
solve[destruct H5; congruence].
simpl in H2.
destruct (eq_nat_dec j0 j0); try solve[elimtype False; omega].
rewrite dependent_types_nonsense in H2; inversion H2; subst c1.
destruct s2.
simpl in *.
unfold find_core in *.
destruct stack0; try solve[congruence].
destruct f.
destruct (eq_nat_dec j0 i0); try solve[elimtype False; omega]; subst.
rewrite dependent_types_nonsense in H3; inversion H3; subst c0.
destruct H1 as [RR [H1 H7]].
simpl in *.
destruct stack0.
simpl in RR.
inv RR.
destruct f.
admit. (*will need to update R_inv to ensure caller state remains invariant
          (and matches across compilation) over calls*)

admit. (*match_others...*)
Qed.

End LinkerCompilable.


  
