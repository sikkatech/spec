-------------------------- MODULE LCDetector_003_draft -----------------------------
EXTENDS Integers

\* the parameters of Light Client
CONSTANTS
  AllNodes,
    (* a set of all nodes that can act as validators (correct and faulty) *)
  TRUSTED_HEIGHT,
    (* an index of the block header that the light client trusts by social consensus *)
  TARGET_HEIGHT,
    (* an index of the block header that the light client tries to verify *)
  TRUSTING_PERIOD,
    (* the period within which the validators are trusted *)
  FAULTY_RATIO,
    (* a pair <<a, b>> that limits that ratio of faulty validator in the blockchain
       from above (exclusive). Tendermint security model prescribes 1 / 3. *)
  IS_PRIMARY_CORRECT,
  IS_SECONDARY_CORRECT

VARIABLES
  blockchain,           (* the reference blockchain *)
  now,                  (* current time *)
  Faulty,               (* the set of faulty validators *)
  fetchedLightBlocks1,  (* a function from heights to LightBlocks *)
  lightBlockStatus1,    (* a function from heights to block statuses *)
  fetchedLightBlocks2,  (* a function from heights to LightBlocks *)
  lightBlockStatus2     (* a function from heights to block statuses *)

vars == <<blockchain, now, Faulty,
          fetchedLightBlocks1, lightBlockStatus1,
          fetchedLightBlocks2, lightBlockStatus2>>

ULTIMATE_HEIGHT == TARGET_HEIGHT + 1 
 
BC == INSTANCE Blockchain_003_draft
    WITH ULTIMATE_HEIGHT <- (TARGET_HEIGHT + 1)

LC1 == INSTANCE LCVerificationApi_003_draft WITH
    IS_PEER_CORRECT <- IS_PRIMARY_CORRECT,
    fetchedLightBlocks <- fetchedLightBlocks1,
    lightBlockStatus <- lightBlockStatus1

LC2 == INSTANCE LCVerificationApi_003_draft WITH
    IS_PEER_CORRECT <- IS_SECONDARY_CORRECT,
    fetchedLightBlocks <- fetchedLightBlocks2,
    lightBlockStatus <- lightBlockStatus2

InitLightBlocks(lb, Heights) ==
    \* BC!LightBlocks is an infinite set, as time is not restricted.
    \* Hence, we initialize the light blocks by picking the sets inside.
    \E vs, nextVS, lastCommit, commit \in [Heights -> SUBSET AllNodes]:
      \* although [Heights -> Int] is an infinite set,
      \* Apalache needs just one instance of this set, so it does not complain.
      \E timestamp \in [Heights -> Int]:
        LET hdr(h) ==
             [height |-> h,
              time |-> timestamp[h],
              VS |-> vs[h],
              NextVS |-> nextVS[h],
              lastCommit |-> lastCommit[h]]
        IN
        LET lightHdr(h) ==
            [header |-> hdr(h), Commits |-> commit[h]]
        IN
        lb = [ h \in Heights |-> lightHdr(h) ]

Init ==
    \* initialize the blockchain to TARGET_HEIGHT + 1
    /\ BC!InitToHeight(FAULTY_RATIO)
    \* precompute a possible result of light client verification for the primary
    /\ \E Heights1 \in SUBSET(TRUSTED_HEIGHT..TARGET_HEIGHT):
        /\ TRUSTED_HEIGHT \in Heights1
        /\ TARGET_HEIGHT \in Heights1
        /\ InitLightBlocks(fetchedLightBlocks1, Heights1)
        \* As we have a non-deterministic scheduler, for every trace that has
        \* an unverified block, there is a filtered trace that only has verified
        \* blocks. This is a deep observation.
        /\ lightBlockStatus1 \in [Heights1 -> {"StateVerified"}]
        /\ LC1!VerifyToTargetPost(TRUSTED_HEIGHT, TARGET_HEIGHT, "finishedSuccess")
    \* initialize the data structures of the secondary
    /\ LET trustedBlock == blockchain[TRUSTED_HEIGHT]
           trustedLightBlock == [header |-> trustedBlock, Commits |-> AllNodes]
       IN
       fetchedLightBlocks2 = [h \in {TRUSTED_HEIGHT} |-> trustedLightBlock]
    /\ lightBlockStatus2 = [h \in {TRUSTED_HEIGHT} |-> "StateVerified"]

Next ==
    UNCHANGED vars

====================================================================================
