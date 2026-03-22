---------------------------- MODULE counterexample ----------------------------

EXTENDS raft_test

(* Constant initialization state *)
ConstInit == TRUE

(* Initial state [_transition(0)] *)
State0 ==
  raft_test_raft_currentTerm
      = SetAsFun({ <<"n1", 0>>, <<"n2", 0>>, <<"n3", 0>> })
    /\ raft_test_raft_logs
      = SetAsFun({ <<"n1", <<>>>>, <<"n2", <<>>>>, <<"n3", <<>>>> })
    /\ raft_test_raft_role
      = SetAsFun({ <<"n1", Variant("Follower", [tag |-> "UNIT"])>>,
        <<"n2", Variant("Follower", [tag |-> "UNIT"])>>,
        <<"n3", Variant("Follower", [tag |-> "UNIT"])>> })
    /\ raft_test_raft_votedFor
      = SetAsFun({ <<"n1", Variant("None", [tag |-> "UNIT"])>>,
        <<"n2", Variant("None", [tag |-> "UNIT"])>>,
        <<"n3", Variant("None", [tag |-> "UNIT"])>> })
    /\ raft_test_raft_votesReceived
      = SetAsFun({ <<"n1", {}>>, <<"n2", {}>>, <<"n3", {}>> })

(* State1 [_transition(0)] *)
State1 ==
  raft_test_raft_currentTerm
      = SetAsFun({ <<"n1", 0>>, <<"n2", 1>>, <<"n3", 0>> })
    /\ raft_test_raft_logs
      = SetAsFun({ <<"n1", <<>>>>, <<"n2", <<>>>>, <<"n3", <<>>>> })
    /\ raft_test_raft_role
      = SetAsFun({ <<"n1", Variant("Follower", [tag |-> "UNIT"])>>,
        <<"n2", Variant("Candidate", [tag |-> "UNIT"])>>,
        <<"n3", Variant("Follower", [tag |-> "UNIT"])>> })
    /\ raft_test_raft_votedFor
      = SetAsFun({ <<"n1", Variant("None", [tag |-> "UNIT"])>>,
        <<"n2", Variant("Some", "n2")>>,
        <<"n3", Variant("None", [tag |-> "UNIT"])>> })
    /\ raft_test_raft_votesReceived
      = SetAsFun({ <<"n1", {}>>, <<"n2", {"n2"}>>, <<"n3", {}>> })

(* State2 [_transition(1)] *)
State2 ==
  raft_test_raft_currentTerm
      = SetAsFun({ <<"n1", 0>>, <<"n2", 1>>, <<"n3", 1>> })
    /\ raft_test_raft_logs
      = SetAsFun({ <<"n1", <<>>>>, <<"n2", <<>>>>, <<"n3", <<>>>> })
    /\ raft_test_raft_role
      = SetAsFun({ <<"n1", Variant("Follower", [tag |-> "UNIT"])>>,
        <<"n2", Variant("Candidate", [tag |-> "UNIT"])>>,
        <<"n3", Variant("Follower", [tag |-> "UNIT"])>> })
    /\ raft_test_raft_votedFor
      = SetAsFun({ <<"n1", Variant("None", [tag |-> "UNIT"])>>,
        <<"n2", Variant("Some", "n2")>>,
        <<"n3", Variant("Some", "n2")>> })
    /\ raft_test_raft_votesReceived
      = SetAsFun({ <<"n1", {}>>, <<"n2", { "n2", "n3" }>>, <<"n3", {}>> })

(* State3 [_transition(2)] *)
State3 ==
  raft_test_raft_currentTerm
      = SetAsFun({ <<"n1", 0>>, <<"n2", 1>>, <<"n3", 1>> })
    /\ raft_test_raft_logs
      = SetAsFun({ <<"n1", <<>>>>, <<"n2", <<>>>>, <<"n3", <<>>>> })
    /\ raft_test_raft_role
      = SetAsFun({ <<"n1", Variant("Follower", [tag |-> "UNIT"])>>,
        <<"n2", Variant("Leader", [tag |-> "UNIT"])>>,
        <<"n3", Variant("Follower", [tag |-> "UNIT"])>> })
    /\ raft_test_raft_votedFor
      = SetAsFun({ <<"n1", Variant("None", [tag |-> "UNIT"])>>,
        <<"n2", Variant("Some", "n2")>>,
        <<"n3", Variant("Some", "n2")>> })
    /\ raft_test_raft_votesReceived
      = SetAsFun({ <<"n1", {}>>, <<"n2", { "n2", "n3" }>>, <<"n3", {}>> })

(* State4 [_transition(0)] *)
State4 ==
  raft_test_raft_currentTerm
      = SetAsFun({ <<"n1", 0>>, <<"n2", 1>>, <<"n3", 2>> })
    /\ raft_test_raft_logs
      = SetAsFun({ <<"n1", <<>>>>, <<"n2", <<>>>>, <<"n3", <<>>>> })
    /\ raft_test_raft_role
      = SetAsFun({ <<"n1", Variant("Follower", [tag |-> "UNIT"])>>,
        <<"n2", Variant("Leader", [tag |-> "UNIT"])>>,
        <<"n3", Variant("Candidate", [tag |-> "UNIT"])>> })
    /\ raft_test_raft_votedFor
      = SetAsFun({ <<"n1", Variant("None", [tag |-> "UNIT"])>>,
        <<"n2", Variant("Some", "n2")>>,
        <<"n3", Variant("Some", "n3")>> })
    /\ raft_test_raft_votesReceived
      = SetAsFun({ <<"n1", {}>>, <<"n2", { "n2", "n3" }>>, <<"n3", {"n3"}>> })

(* State5 [_transition(1)] *)
State5 ==
  raft_test_raft_currentTerm
      = SetAsFun({ <<"n1", 2>>, <<"n2", 1>>, <<"n3", 2>> })
    /\ raft_test_raft_logs
      = SetAsFun({ <<"n1", <<>>>>, <<"n2", <<>>>>, <<"n3", <<>>>> })
    /\ raft_test_raft_role
      = SetAsFun({ <<"n1", Variant("Follower", [tag |-> "UNIT"])>>,
        <<"n2", Variant("Leader", [tag |-> "UNIT"])>>,
        <<"n3", Variant("Candidate", [tag |-> "UNIT"])>> })
    /\ raft_test_raft_votedFor
      = SetAsFun({ <<"n1", Variant("Some", "n3")>>,
        <<"n2", Variant("Some", "n2")>>,
        <<"n3", Variant("Some", "n3")>> })
    /\ raft_test_raft_votesReceived
      = SetAsFun({ <<"n1", {}>>,
        <<"n2", { "n2", "n3" }>>,
        <<"n3", { "n1", "n3" }>> })

(* State6 [_transition(2)] *)
State6 ==
  raft_test_raft_currentTerm
      = SetAsFun({ <<"n1", 2>>, <<"n2", 1>>, <<"n3", 2>> })
    /\ raft_test_raft_logs
      = SetAsFun({ <<"n1", <<>>>>, <<"n2", <<>>>>, <<"n3", <<>>>> })
    /\ raft_test_raft_role
      = SetAsFun({ <<"n1", Variant("Follower", [tag |-> "UNIT"])>>,
        <<"n2", Variant("Leader", [tag |-> "UNIT"])>>,
        <<"n3", Variant("Leader", [tag |-> "UNIT"])>> })
    /\ raft_test_raft_votedFor
      = SetAsFun({ <<"n1", Variant("Some", "n3")>>,
        <<"n2", Variant("Some", "n2")>>,
        <<"n3", Variant("Some", "n3")>> })
    /\ raft_test_raft_votesReceived
      = SetAsFun({ <<"n1", {}>>,
        <<"n2", { "n2", "n3" }>>,
        <<"n3", { "n1", "n3" }>> })

(* The following formula holds true in the last state and violates the invariant *)
InvariantViolation ==
  LET t_6 ==
    {
      raft_test_raft_n_285_2 \in { "n1", "n2", "n3" }:
        raft_test_raft_role[raft_test_raft_n_285_2]
          = Variant("Leader", [tag |-> "UNIT"])
    }
  IN
  Skolem((\E t_4 \in t_6: Skolem((\E t_5 \in t_6: ~(t_4 = t_5)))))

================================================================================
(* Created by Apalache on Thu Mar 12 15:08:34 IST 2026 *)
(* https://github.com/apalache-mc/apalache *)
