# V RFCs

Many changes, including bug fixes and documentation improvements can be implemented and reviewed via the normal GitHub pull request workflow.

Some changes though are significant, and we ask that these be put through a bit of a design process and produce a consensus among the community.

The [*RFC*](https://en.wikipedia.org/wiki/Request_for_Comments) (request for comments) process is intended to provide a consistent and controlled path for new features to enter the language and standard libraries, so that all stakeholders can be confident about the direction the language is evolving in.

## RFC proposal process

In short, to get a major added feature, one must first get the RFC merged into the RFC repository as a markdown file. At that point the RFC is "active" and may be implemented with the goal of eventual inclusion into V.
In long, RFC process is very simple. It takes just 12 steps!

  - Fork the RFC repo [RFC repository](https://github.com/vlang/rfcs/)
  - Copy `000-template.md` to `rfcs/000-my-proposal` (where "my-proposal" is descriptive name). Don't assign an RFC number yet; This is going to be the PR number and we'll rename the file accordingly if the RFC is accepted.
  - Fill in the RFC. Put care into the details: RFCs that do not present convincing motivation, demonstrate lack of understanding of the design's impact, or are disingenuous about the drawbacks or alternatives tend to be poorly-received. 
  - Submit a pull request. As a pull request the RFC will receive design feedback from the larger community, and the author should be prepared to revise it in response.
  - Now that your RFC has an open pull request, use the issue number of the PR to update your `000-` prefix to that number.
  - Each pull request will be labeled with the most relevant reviewers of vlang organization, which will lead to its being triaged by him.
  - Build consensus and integrate feedback. RFCs that have broad support are much more likely to make progress than those that don't receive any comments. Feel free to reach out to the RFC assignee in particular to get help identifying stakeholders and obstacles.
  - The reviewers will discuss the RFC pull request, as much as possible in the comment thread of the pull request itself. Offline discussion will be summarized on the pull request comment thread.
  - RFCs rarely go through this process unchanged, especially as alternatives and drawbacks are shown. You can make edits, big and small, to the RFC to clarify or change the design, but make changes as new commits to the pull request, and leave a comment on the pull request explaining your changes. Specifically, do not squash or rebase commits after they are visible on the pull request.
  - At some point, one of the reviewers will propose a "motion for final comment period" (FCP), along with a disposition for the RFC (merge, close, or postpone). 
    - This step is taken when enough of the tradeoffs have been discussed that the main reviewer is in a position to make a decision. That does not require consensus amongst all participants in the RFC thread (which is usually impossible). However, the argument supporting the disposition on the RFC needs to have already been clearly articulated, and there should not be a strong consensus against that position outside of the reviewers. Reviewers use their best judgment in taking this step, and the FCP itself ensures there is ample time and notification for stakeholders to push back if it is made prematurely.
    - For RFCs with lengthy discussion, the motion to FCP is usually preceded by a summary comment trying to lay out the current state of the discussion and major tradeoffs/points of disagreement.
    - Before actually entering FCP, all reviewers must sign off; this is often the point at which many reviewers first review the RFC in full depth.
  - The FCP lasts ten calendar days, so that it is open for at least 5 business days. It is also advertised widely in corresponding channel of [discord server](https://discord.gg/3Jx28bdY3z). This way all stakeholders have a chance to lodge any final objections before a decision is reached.
  - In most cases, the FCP period is quiet, and the RFC is either merged or closed. However, sometimes substantial new arguments or ideas are raised, the FCP is canceled, and the RFC goes back into development mode.

## Requirements for specific RFC types
  - [language changes](#)
  - [library changes](#)
  - [compiler changes](#)

# FAQ

## When I need to write RFC?

>  <b style="color:yellow">WARNING:</b> If you submit a pull request to implement a new feature without going through the RFC process, it may be closed with a polite request to submit an RFC first.

You need to follow this process if you intend to make significant changes to repos in vlang organization in github. What constitutes a significant change is evolving based on community norms and varies depending on what part of the ecosystem you are proposing to change, but may include the following.

  - Any semantic or syntactic change to the language that is not a bugfix.
  - Removing language features, including those that are feature-gated.
  - Changes to the interface between the compiler and libraries, including lang items and intrinsics.
  - Additions to `vlib`.
  - Vlang organization management.

Some changes do not require an RFC:

  - Rephrasing, reorganizing, refactoring, or otherwise "changing shape does not change meaning".
  - Additions that strictly improve objective, numerical quality criteria (warning removal, speedup, better platform coverage, more parallelism, handle more errors, ...)
  - Additions only likely to be _noticed by_ other developers-of-v, invisible to users-of-v.
  
## How the rfc check process works?

While the RFC pull request is up, the reviewers may schedule meetings with the author and/or relevant stakeholders to discuss the issues in greater detail, and in some cases the topic may be discussed at a reviewers meeting. In either case a summary from the meeting will be posted back to the RFC pull request.

The reviewers makes final decisions about RFCs after the benefits and drawbacks are well understood. These decisions can be made at any time, but reviewers will regularly issue decisions. When a decision is made, the RFC pull request will either be merged or closed. In either case, if the reasoning is not clear from the discussion in thread, the reviewer will add a comment describing the rationale for the decision.

## Who can implement RFC?

The author of an RFC is not obligated to implement it. Of course, the RFC author (like any other developer) is welcome to post an implementation for review after the RFC has been accepted.

If you are interested in working on the implementation for an "active" RFC, but cannot determine if someone else is already working on it, feel free to ask (e.g. by leaving a comment on the associated issue).

Some accepted RFCs represent vital features that need to be implemented right away. Other accepted RFCs can represent features that can wait until some arbitrary developer feels like doing the work. Every accepted RFC has an associated issue tracking its implementation in the V repository; thus that associated issue can be assigned a priority via the triage process that the team uses for all issues in the V repository.

## What is postponement RFC?

Usually an RFC pull request marked as "postponed" has already passed an informal first round of evaluation, namely the round of "do we think we would ever possibly consider making this change, as outlined in the RFC pull request, or some semi-obvious variation of it." (When the answer to the latter question is "no", then the appropriate response is to close the RFC, not postpone it.)

Some RFC pull requests are tagged with the "postponed" label when they are closed (as part of the rejection process). An RFC closed with "postponed" is marked as such because we want neither to think about evaluating the proposal nor about implementing the described feature until some time in the future, and we believe that we can afford to wait until then to do so. Historically, "postponed" was used to postpone features until after 1.0. Postponed pull requests may be re-opened when the time is right. We don't have any formal process for that, you should ask reviewers.
