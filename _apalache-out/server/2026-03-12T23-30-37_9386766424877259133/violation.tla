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
      = SetAsFun({ <<"n1", 0>>, <<"n2", 0>>, <<"n3", 1>> })
    /\ raft_test_raft_logs
      = SetAsFun({ <<"n1", <<>>>>, <<"n2", <<>>>>, <<"n3", <<>>>> })
    /\ raft_test_raft_role
      = SetAsFun({ <<"n1", Variant("Follower", [tag |-> "UNIT"])>>,
        <<"n2", Variant("Follower", [tag |-> "UNIT"])>>,
        <<"n3", Variant("Candidate", [tag |-> "UNIT"])>> })
    /\ raft_test_raft_votedFor
      = SetAsFun({ <<"n1", Variant("None", [tag |-> "UNIT"])>>,
        <<"n2", Variant("None", [tag |-> "UNIT"])>>,
        <<"n3", Variant("Some", "n3")>> })
    /\ raft_test_raft_votesReceived
      = SetAsFun({ <<"n1", {}>>, <<"n2", {}>>, <<"n3", {"n3"}>> })

(* State2 [_transition(1)] *)
State2 ==
  raft_test_raft_currentTerm
      = SetAsFun({ <<"n1", 0>>, <<"n2", 1>>, <<"n3", 1>> })
    /\ raft_test_raft_logs
      = SetAsFun({ <<"n1", <<>>>>, <<"n2", <<>>>>, <<"n3", <<>>>> })
    /\ raft_test_raft_role
      = SetAsFun({ <<"n1", Variant("Follower", [tag |-> "UNIT"])>>,
        <<"n2", Variant("Follower", [tag |-> "UNIT"])>>,
        <<"n3", Variant("Candidate", [tag |-> "UNIT"])>> })
    /\ raft_test_raft_votedFor
      = SetAsFun({ <<"n1", Variant("None", [tag |-> "UNIT"])>>,
        <<"n2", Variant("Some", "n3")>>,
        <<"n3", Variant("Some", "n3")>> })
    /\ raft_test_raft_votesReceived
      = SetAsFun({ <<"n1", {}>>, <<"n2", {}>>, <<"n3", { "n2", "n3" }>> })

(* State3 [_transition(0)] *)
State3 ==
  raft_test_raft_currentTerm
      = SetAsFun({ <<"n1", 0>>, <<"n2", 2>>, <<"n3", 1>> })
    /\ raft_test_raft_logs
      = SetAsFun({ <<"n1", <<>>>>, <<"n2", <<>>>>, <<"n3", <<>>>> })
    /\ raft_test_raft_role
      = SetAsFun({ <<"n1", Variant("Follower", [tag |-> "UNIT"])>>,
        <<"n2", Variant("Candidate", [tag |-> "UNIT"])>>,
        <<"n3", Variant("Candidate", [tag |-> "UNIT"])>> })
    /\ raft_test_raft_votedFor
      = SetAsFun({ <<"n1", Variant("None", [tag |-> "UNIT"])>>,
        <<"n2", Variant("Some", "n2")>>,
        <<"n3", Variant("Some", "n3")>> })
    /\ raft_test_raft_votesReceived
      = SetAsFun({ <<"n1", {}>>, <<"n2", {"n2"}>>, <<"n3", { "n2", "n3" }>> })

(* State4 [_transition(1)] *)
State4 ==
  raft_test_raft_currentTerm
      = SetAsFun({ <<"n1", 2>>, <<"n2", 2>>, <<"n3", 1>> })
    /\ raft_test_raft_logs
      = SetAsFun({ <<"n1", <<>>>>, <<"n2", <<>>>>, <<"n3", <<>>>> })
    /\ raft_test_raft_role
      = SetAsFun({ <<"n1", Variant("Follower", [tag |-> "UNIT"])>>,
        <<"n2", Variant("Candidate", [tag |-> "UNIT"])>>,
        <<"n3", Variant("Candidate", [tag |-> "UNIT"])>> })
    /\ raft_test_raft_votedFor
      = SetAsFun({ <<"n1", Variant("Some", "n2")>>,
        <<"n2", Variant("Some", "n2")>>,
        <<"n3", Variant("Some", "n3")>> })
    /\ raft_test_raft_votesReceived
      = SetAsFun({ <<"n1", {}>>,
        <<"n2", { "n1", "n2" }>>,
        <<"n3", { "n2", "n3" }>> })

(* State5 [_transition(0)] *)
State5 ==
  raft_test_raft_currentTerm
      = SetAsFun({ <<"n1", 3>>, <<"n2", 2>>, <<"n3", 1>> })
    /\ raft_test_raft_logs
      = SetAsFun({ <<"n1", <<>>>>, <<"n2", <<>>>>, <<"n3", <<>>>> })
    /\ raft_test_raft_role
      = SetAsFun({ <<"n1", Variant("Candidate", [tag |-> "UNIT"])>>,
        <<"n2", Variant("Candidate", [tag |-> "UNIT"])>>,
        <<"n3", Variant("Candidate", [tag |-> "UNIT"])>> })
    /\ raft_test_raft_votedFor
      = SetAsFun({ <<"n1", Variant("Some", "n1")>>,
        <<"n2", Variant("Some", "n2")>>,
        <<"n3", Variant("Some", "n3")>> })
    /\ raft_test_raft_votesReceived
      = SetAsFun({ <<"n1", {"n1"}>>,
        <<"n2", { "n1", "n2" }>>,
        <<"n3", { "n2", "n3" }>> })

(* State6 [_transition(2)] *)
State6 ==
  raft_test_raft_currentTerm
      = SetAsFun({ <<"n1", 3>>, <<"n2", 2>>, <<"n3", 1>> })
    /\ raft_test_raft_logs
      = SetAsFun({ <<"n1", <<>>>>, <<"n2", <<>>>>, <<"n3", <<>>>> })
    /\ raft_test_raft_role
      = SetAsFun({ <<"n1", Variant("Candidate", [tag |-> "UNIT"])>>,
        <<"n2", Variant("Candidate", [tag |-> "UNIT"])>>,
        <<"n3", Variant("Leader", [tag |-> "UNIT"])>> })
    /\ raft_test_raft_votedFor
      = SetAsFun({ <<"n1", Variant("Some", "n1")>>,
        <<"n2", Variant("Some", "n2")>>,
        <<"n3", Variant("Some", "n3")>> })
    /\ raft_test_raft_votesReceived
      = SetAsFun({ <<"n1", {"n1"}>>,
        <<"n2", { "n1", "n2" }>>,
        <<"n3", { "n2", "n3" }>> })

(* State7 [_transition(2)] *)
State7 ==
  raft_test_raft_currentTerm
      = SetAsFun({ <<"n1", 3>>, <<"n2", 2>>, <<"n3", 1>> })
    /\ raft_test_raft_logs
      = SetAsFun({ <<"n1", <<>>>>, <<"n2", <<>>>>, <<"n3", <<>>>> })
    /\ raft_test_raft_role
      = SetAsFun({ <<"n1", Variant("Candidate", [tag |-> "UNIT"])>>,
        <<"n2", Variant("Leader", [tag |-> "UNIT"])>>,
        <<"n3", Variant("Follower", [tag |-> "UNIT"])>> })
    /\ raft_test_raft_votedFor
      = SetAsFun({ <<"n1", Variant("Some", "n1")>>,
        <<"n2", Variant("Some", "n2")>>,
        <<"n3", Variant("Some", "n3")>> })
    /\ raft_test_raft_votesReceived
      = SetAsFun({ <<"n1", {"n1"}>>,
        <<"n2", { "n1", "n2" }>>,
        <<"n3", { "n2", "n3" }>> })

(* State8 [_transition(0)] *)
State8 ==
  raft_test_raft_currentTerm
      = SetAsFun({ <<"n1", 3>>, <<"n2", 2>>, <<"n3", 2>> })
    /\ raft_test_raft_logs
      = SetAsFun({ <<"n1", <<>>>>, <<"n2", <<>>>>, <<"n3", <<>>>> })
    /\ raft_test_raft_role
      = SetAsFun({ <<"n1", Variant("Candidate", [tag |-> "UNIT"])>>,
        <<"n2", Variant("Leader", [tag |-> "UNIT"])>>,
        <<"n3", Variant("Candidate", [tag |-> "UNIT"])>> })
    /\ raft_test_raft_votedFor
      = SetAsFun({ <<"n1", Variant("Some", "n1")>>,
        <<"n2", Variant("Some", "n2")>>,
        <<"n3", Variant("Some", "n3")>> })
    /\ raft_test_raft_votesReceived
      = SetAsFun({ <<"n1", {"n1"}>>, <<"n2", { "n1", "n2" }>>, <<"n3", {"n3"}>> })

(* The following formula holds true in the last state and violates the invariant *)
InvariantViolation == TRUE

================================================================================
(* Created by Apalache on Thu Mar 12 23:30:46 IST 2026 *)
(* https://github.com/apalache-mc/apalache *)
