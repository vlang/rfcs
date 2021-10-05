- Topic Name: rfc-process
- Start Date: 2021-10-03
- RFC PR: [vlang/rfcs#00000](https://github.com/vlang/rfcs/pull/00000)
- V Issue: N/A

# Summary

The "RFC" (request for comments) process is intended to provide a consistent and controlled path for new features to enter the language and standard libraries, so that all stakeholders can be confident about the direction the language is evolving in.

# Motivation

Many changes, including bug fixes and documentation improvements can be implemented and reviewed via the normal GitHub pull request workflow.

Some changes though are significant, and we ask that these be put through a bit of a design process and produce a consensus among the V community.

# Guide-level explanation

You need to follow this process if you intend to make significant changes to the V distribution. What constitutes a "substantial" change is evolving based on community norms, but may include the following.

  - Any semantic or syntactic change to the language that is not a bugfix.
  - Removing language features, including those that are feature-gated.
  - Changes to the interface between the compiler and libraries, including lang items and intrinsics.
  - Additions to std

Some changes do not require an RFC:

  - Rephrasing, reorganizing, refactoring, or otherwise "changing shape does not change meaning".
  - Additions that strictly improve objective, numerical quality criteria (warning removal, speedup, better platform coverage, more parallelism, trap more errors, etc.)
  - Additions only likely to be noticed by other developers-of-v, invisible to users-of-v.

If you submit a pull request to implement a new feature without going through the RFC process, it may be closed with a polite request to submit an RFC first.

# Reference-level explanation

In short, to get a major feature added to V, one must first get the RFC merged into the RFC repo as a markdown file. At that point the RFC is 'active' and may be implemented with the goal of eventual inclusion into V.

  - Fork the RFC repo https://github.com/vlang/rfcs
  - Copy `000-template.md` to `text/000-my-feature.md` (where 'my-feature' is descriptive. don't assign an RFC number yet).
  - Fill in the RFC
  - Submit a pull request. The pull request is the time to get review of the design from the larger community.
  - Build consensus and integrate feedback. RFCs that have broad support are much more likely to make progress than those that don't receive any comments.

Eventually, somebody on the core team will either accept the RFC by merging the pull request, at which point the RFC is 'active', or reject it by closing the pull request.

Whomever merges the RFC should do the following:

  - Assign an id, using the PR number of the RFC pull request. (If the RFC has multiple pull requests associated with it, choose one PR number, preferably the minimal one.)
  - Add the file in the text/ directory.
  - Create a corresponding issue on V repo
  - Fill in the remaining metadata in the RFC header, including links for the original pull request(s) and the newly created V issue.
  - Add an entry in the Active RFC List of the root README.md.
  - Commit everything.

Once an RFC becomes active then authors may implement it and submit the feature as a pull request to the V repo. An 'active' is not a rubber stamp, and in particular still does not mean the feature will ultimately be merged; it does mean that in principle all the major stakeholders have agreed to the feature and are amenable to merging it.

Modifications to active RFC's can be done in followup PR's. An RFC that makes it through the entire process to implementation is considered 'complete' and is removed from the Active RFC List; an RFC that fails after becoming active is 'inactive' and moves to the 'inactive' folder.

# Drawbacks

The only reason why we should not do this is that this process will take longer than dealing with just pull requests. But without a new rfc process, it will be more difficult to keep track of changes to the language.

# Rationale and alternatives

Retain the current informal RFC process. The newly proposed RFC process is designed to improve over the informal process in the following ways:

  - Discourage unactionable or vague RFCs
  - Ensure that all serious RFCs are considered equally
  - Give confidence to those with a stake in V development that they understand why new features are being merged

As an alternative, we could adopt an even stricter RFC process than the one proposed here. If desired, we should likely look to Python's [PEP](http://legacy.python.org/dev/peps/pep-0001/) process for inspiration.

# Unresolved questions

- What parts of the design do you expect to resolve through the RFC process before this gets merged?
- What parts of the design do you expect to resolve through the implementation of this feature before stabilization?
- What related issues do you consider out of scope for this RFC that could be addressed in the future independently of the solution that comes out of this RFC?

# Future possibilities

I don't see much scope or need to improve this RFC, as it is taken almost entirely from [rust-lang/rfcs](https://github.com/rust-lang/rfcs/blob/master/text/0002-rfc-process.md), where it has been sufficiently discussed.
