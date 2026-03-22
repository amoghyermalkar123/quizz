module raft {
  // define types and structure for our raft protocol
  type NodeId = str
  type Term = int

  type NodeRole = Follower | Candidate | Leader

  type Data = {
    command: str,
    key: str,
    value: str
  }

  type Log = {
    index: int,
    term: Term,
    data: Data
  }

  type Option[a] = 
    | Some(a)
    | None

  type Vote = Option[NodeId]

  // Now we define states

  // quint specs model `state` that changes over time
  // below are our per-node states that change each time
  // a log is replicated across the cluster

  // this says that each node in the cluster has it's own
  // term, role and list of logs
  var currentTerm: NodeId -> Term
  var role: NodeId -> NodeRole
  var logs: NodeId -> List[Log]
  var votedFor: NodeId -> Vote
  var votesReceived: NodeId -> Set[NodeId]

  // definint a cluster
  const Nodes: Set[NodeId]

  // now we define actions
  // actions are what causes state to transition from one state to another

  // a special action to define initial states
  action init = all {
      currentTerm' = Nodes.mapBy(n => 0),
      role' = Nodes.mapBy(n => Follower),
      logs' = Nodes.mapBy(n => List()),
      votedFor' = Nodes.mapBy(n => None),
      votesReceived' = Nodes.mapBy(n => Set())
  }

  action step = any {
    nondet candidate = Nodes.oneOf()
    becomeCandidate(candidate),

    nondet voter = Nodes.oneOf()
    nondet candidate = Nodes.oneOf()
    grantVote(voter, candidate),

    nondet node = Nodes.oneOf()
    becomeLeader(node),
    
    stutter
  }

  action becomeCandidate(node: NodeId): bool = all  {
    role.get(node) == Follower,
    currentTerm' = currentTerm.set(node, currentTerm.get(node) + 1),
    role' = role.set(node, Candidate),
    logs' = logs,
    // vote for self
    votedFor' = votedFor.set(node, Some(node)),
    // add self vote to received map
    votesReceived' = votesReceived.set(node, Set(node))
  }

  action stutter: bool = all {
    currentTerm' = currentTerm,
    role' = role,
    logs' = logs,
    votedFor' = votedFor,
    votesReceived' = votesReceived
   }

  action becomeLeader(node: NodeId): bool = all {
     // ensure node is already a candidate
     role.get(node) == Candidate,

     // check quorum
     votesReceived.get(node).size() > Nodes.size() / 2,

     // only allow node to become leader if it's term is higher than all others 
     // update roles for all the nodes in the cluster
     role' = role.keys().mapBy(n => 
        // if the node is the one that just got quorum, become leader
        if (n == node) Leader
        // if the node is currently already leader but it's current term is lower
        // than the new `node`, step down to follower
        else if (role.get(n) == Leader and currentTerm.get(n) < currentTerm.get(node)) Follower
        // otherwise the role remains the same
        else role.get(n)
     ),

     // remains same
     currentTerm' = currentTerm,
     logs' = logs,
     votedFor' = votedFor,
     votesReceived' = votesReceived,
  }

  action grantVote(voter: NodeId, candidate: NodeId): bool = all {
     // guards
     role.get(candidate) == Candidate,
     votedFor.get(voter) == None,
     currentTerm.get(candidate) >= currentTerm.get(voter),

     // transitions
     currentTerm' = currentTerm.set(voter, currentTerm.get(candidate)),
     votedFor' = votedFor.set(voter, Some(candidate)),
     votesReceived' = votesReceived.set(candidate, votesReceived.get(candidate).union(Set(voter))),

     // remains same
     logs' = logs,
     role' = role
  }


  // define invariants
  // this is the core of the spec, i.e. for each run/ trace of
  // of our raft spec, the mentioned invariants should always hold true
  // no violation should happen and this is how we define a safe system


  // invariant: electionSafety
  // description: the result of an election process should always
  // result in either none or at most max 1 leader elected as a result
  // of said election process.
  val electionSafety: bool = Nodes.filter(n => role.get(n) == Leader).size() <= 1
}

module raft_test {
      import raft(Nodes = Set("n1", "n2", "n3")).*
}
