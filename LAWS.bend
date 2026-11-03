# episteme's laws. Each guarantee is one file under laws/, its prose on top
# and its quantified laws under it, proved by the file of the same name under
# proofs/; LAWS.bend and PROOF.bend only import them. The gate: the first line
# `bend PROOF.bend` prints is exactly `ALL PROOFS CHECK`. Tests and fixtures
# are never evidence for a guarantee; what episteme cannot prove is said where
# it is assumed, on the code (`# Trusted, not proved:`).
#
# The guarantees are about the pure core under src/. The law and proof files
# import those modules and nothing that does IO. The IO shell (src/store.bend,
# src/ingest.bend, src/conn/, src/reader.bend, src/pool.bend, src/ask.bend,
# src/gold.bend, src/eval.bend, main.bend) only runs what the core decides;
# what it does is trusted in each module's header, tests/smoke.sh runs it end
# to end on a synthetic book, a synthetic transcript, a fake Honcho, synthetic
# git repos and an intent file, and tests/live.sh, run by hand, runs the
# reader pool against live readers.
#
# The first file of each family opens with what the family is about:
# laws/ParagraphsAreNonBlankRuns.bend (paragraphs),
# laws/MakeNeedsAParagraph.bend (records),
# laws/ShardsCoverEveryParagraph.bend (shards),
# laws/ShardHoldsOneSource.bend (shards split by source),
# laws/FilterHitsChosenSources.bend (the filter),
# laws/SinceKeepsRecentShards.bend (--since),
# laws/ResolveKeepsNamedParagraphs.bend (excerpts),
# laws/IngestKeepsRecordsThatFit.bend (ingest),
# laws/DecodeSkipsNonMessages.bend (Claude transcripts),
# laws/HonchoRecordFields.bend (Honcho messages),
# laws/GitRecordFields.bend (git history),
# laws/IntentAppendsOnChange.bend (the intent file),
# laws/RequestAdmitsOnlyLabels.bend (readers and ask) and
# laws/HitsCountRecalled.bend (the eval).
#
# The other law files are closed examples, each one law named for what it
# checks and with no prose (laws/BlankLinesSeparateParagraphs.bend,
# laws/ShardJsonRoundTrips.bend, ...), and
# laws/ShardLabelsNumberParagraphs.bend, a quantified law no guarantee
# claims. They promise nothing beyond the equality each states.
import Base
import ./laws/AfterReadsOnFromCursor.bend as AfterReadsOnFromCursor
import ./laws/AllClaudeChatsRefused.bend as AllClaudeChatsRefused
import ./laws/AssistantLineRecords.bend as AssistantLineRecords
import ./laws/BareDotIsNoSource.bend as BareDotIsNoSource
import ./laws/BlankLinesSeparateParagraphs.bend as BlankLinesSeparateParagraphs
import ./laws/BookPacksIntoShards.bend as BookPacksIntoShards
import ./laws/ChatCursorReadsBack.bend as ChatCursorReadsBack
import ./laws/ChatFilterNamesAProject.bend as ChatFilterNamesAProject
import ./laws/ChatPrefixRefused.bend as ChatPrefixRefused
import ./laws/ChatProjectPasses.bend as ChatProjectPasses
import ./laws/ChatRecordsKeepEveryBlock.bend as ChatRecordsKeepEveryBlock
import ./laws/ChatSourceDirName.bend as ChatSourceDirName
import ./laws/ClaudeCursorReadsBack.bend as ClaudeCursorReadsBack
import ./laws/CutEndsAtLastFeed.bend as CutEndsAtLastFeed
import ./laws/CutReplyFails.bend as CutReplyFails
import ./laws/DecodeSkipsNonMessages.bend as DecodeSkipsNonMessages
import ./laws/EmptyAnswerIsOk.bend as EmptyAnswerIsOk
import ./laws/EmptyIdLineIsNoRecord.bend as EmptyIdLineIsNoRecord
import ./laws/EmptyIntentAppendsNothing.bend as EmptyIntentAppendsNothing
import ./laws/EmptyParasLineIsNoRecord.bend as EmptyParasLineIsNoRecord
import ./laws/EmptyPrefixRefused.bend as EmptyPrefixRefused
import ./laws/EveryShardIsRead.bend as EveryShardIsRead
import ./laws/ExactClaudeChatRefused.bend as ExactClaudeChatRefused
import ./laws/ExcerptsFitBudget.bend as ExcerptsFitBudget
import ./laws/ExcerptsRenderAsText.bend as ExcerptsRenderAsText
import ./laws/ExtendResumesPack.bend as ExtendResumesPack
import ./laws/FailedReadsListed.bend as FailedReadsListed
import ./laws/FilterHitsChosenSources.bend as FilterHitsChosenSources
import ./laws/FilterParseSplitsAndTrims.bend as FilterParseSplitsAndTrims
import ./laws/FinalFeedNotInParagraph.bend as FinalFeedNotInParagraph
import ./laws/FooterNamesFailedShards.bend as FooterNamesFailedShards
import ./laws/FreezingIsStable.bend as FreezingIsStable
import ./laws/FrozenShardsFitCap.bend as FrozenShardsFitCap
import ./laws/FullTailStaysOpen.bend as FullTailStaysOpen
import ./laws/GitCommitRecord.bend as GitCommitRecord
import ./laws/GitCursorReadsBack.bend as GitCursorReadsBack
import ./laws/GitCutDropsAndCounts.bend as GitCutDropsAndCounts
import ./laws/GitCutFits.bend as GitCutFits
import ./laws/GitCutLosesNoLine.bend as GitCutLosesNoLine
import ./laws/GitLogReadsCommits.bend as GitLogReadsCommits
import ./laws/GitMoreCountsDropped.bend as GitMoreCountsDropped
import ./laws/GitReadsPastTips.bend as GitReadsPastTips
import ./laws/GitRecordFields.bend as GitRecordFields
import ./laws/GitTimesAreUtc.bend as GitTimesAreUtc
import ./laws/HitsCountRecalled.bend as HitsCountRecalled
import ./laws/HonchoAlonePasses.bend as HonchoAlonePasses
import ./laws/HonchoCursorReadsBack.bend as HonchoCursorReadsBack
import ./laws/HonchoListIds.bend as HonchoListIds
import ./laws/HonchoNonPageHasNoItems.bend as HonchoNonPageHasNoItems
import ./laws/HonchoPageRecords.bend as HonchoPageRecords
import ./laws/HonchoPlacesAndQueries.bend as HonchoPlacesAndQueries
import ./laws/HonchoReadsOnlyNew.bend as HonchoReadsOnlyNew
import ./laws/HonchoRecordFields.bend as HonchoRecordFields
import ./laws/HonchoStepPages.bend as HonchoStepPages
import ./laws/IngestKeepsRecordsThatFit.bend as IngestKeepsRecordsThatFit
import ./laws/IntentAppendsOnChange.bend as IntentAppendsOnChange
import ./laws/IntentFirstTextRecord.bend as IntentFirstTextRecord
import ./laws/KeepPicksMessageLines.bend as KeepPicksMessageLines
import ./laws/KeepSkipsUnparsedLines.bend as KeepSkipsUnparsedLines
import ./laws/LeadingBlankLinesDropped.bend as LeadingBlankLinesDropped
import ./laws/LinesStopAtLastFeed.bend as LinesStopAtLastFeed
import ./laws/LongParaLineIsNoRecord.bend as LongParaLineIsNoRecord
import ./laws/MakeNeedsAParagraph.bend as MakeNeedsAParagraph
import ./laws/MedianAndMax.bend as MedianAndMax
import ./laws/MedianAndMaxOfTimes.bend as MedianAndMaxOfTimes
import ./laws/MergeJoinsRecordAcrossShards.bend as MergeJoinsRecordAcrossShards
import ./laws/MergeOrdersByTime.bend as MergeOrdersByTime
import ./laws/Non200Fails.bend as Non200Fails
import ./laws/NonJsonReplyFails.bend as NonJsonReplyFails
import ./laws/NonMessageLinesGiveNothing.bend as NonMessageLinesGiveNothing
import ./laws/NoParasLineIsNoRecord.bend as NoParasLineIsNoRecord
import ./laws/NoSinceChangesNothing.bend as NoSinceChangesNothing
import ./laws/NumberIdsFail.bend as NumberIdsFail
import ./laws/OnlyTheLastShardIsOpen.bend as OnlyTheLastShardIsOpen
import ./laws/OrderedTakesFirstRead.bend as OrderedTakesFirstRead
import ./laws/OtherSourceNotRecalled.bend as OtherSourceNotRecalled
import ./laws/OverlapIsRecalled.bend as OverlapIsRecalled
import ./laws/ParagraphOffsetsSliceText.bend as ParagraphOffsetsSliceText
import ./laws/ParagraphsAreNonBlankRuns.bend as ParagraphsAreNonBlankRuns
import ./laws/ParagraphsCutAtMax.bend as ParagraphsCutAtMax
import ./laws/PrefixHitsBook.bend as PrefixHitsBook
import ./laws/PrefixMissesLongerName.bend as PrefixMissesLongerName
import ./laws/ProjectDropsDash.bend as ProjectDropsDash
import ./laws/QueuedNotificationSkipped.bend as QueuedNotificationSkipped
import ./laws/QueuedPromptRead.bend as QueuedPromptRead
import ./laws/RatioRoundsDown.bend as RatioRoundsDown
import ./laws/RecalledMeansOverlap.bend as RecalledMeansOverlap
import ./laws/RecordHeaderAndSize.bend as RecordHeaderAndSize
import ./laws/RecordLineRoundTrips.bend as RecordLineRoundTrips
import ./laws/RecordsSplitOnlyWhenTooBig.bend as RecordsSplitOnlyWhenTooBig
import ./laws/ReplyIsOkOrFailed.bend as ReplyIsOkOrFailed
import ./laws/ReplyReadsLabelsAndTimings.bend as ReplyReadsLabelsAndTimings
import ./laws/RequestAdmitsOnlyLabels.bend as RequestAdmitsOnlyLabels
import ./laws/RunNoticeNamesShards.bend as RunNoticeNamesShards
import ./laws/ResolveCountsUnknownLabels.bend as ResolveCountsUnknownLabels
import ./laws/ResolveKeepsNamedParagraphs.bend as ResolveKeepsNamedParagraphs
import ./laws/SchemaAdmitsShardLabels.bend as SchemaAdmitsShardLabels
import ./laws/ScoreHitsCountsOverlaps.bend as ScoreHitsCountsOverlaps
import ./laws/ShardHoldsOneSource.bend as ShardHoldsOneSource
import ./laws/ShardJsonRefusesBadRange.bend as ShardJsonRefusesBadRange
import ./laws/ShardJsonRefusesEmptyRecord.bend as ShardJsonRefusesEmptyRecord
import ./laws/ShardJsonRefusesMissingUpto.bend as ShardJsonRefusesMissingUpto
import ./laws/ShardJsonRefusesNonArrayItems.bend as ShardJsonRefusesNonArrayItems
import ./laws/ShardJsonRoundTrips.bend as ShardJsonRoundTrips
import ./laws/ShardLabelsNumberParagraphs.bend as ShardLabelsNumberParagraphs
import ./laws/ShardRendersLabelledText.bend as ShardRendersLabelledText
import ./laws/ShardsCoverEveryParagraph.bend as ShardsCoverEveryParagraph
import ./laws/ShardSourcesSorted.bend as ShardSourcesSorted
import ./laws/ShiftMovesOffsets.bend as ShiftMovesOffsets
import ./laws/SinceDateIsMidnight.bend as SinceDateIsMidnight
import ./laws/SinceDropsOldExcerpts.bend as SinceDropsOldExcerpts
import ./laws/SinceKeepsFullTime.bend as SinceKeepsFullTime
import ./laws/SinceKeepsRecentShards.bend as SinceKeepsRecentShards
import ./laws/SinceRefusesNoSeconds.bend as SinceRefusesNoSeconds
import ./laws/SinceRefusesShortMonth.bend as SinceRefusesShortMonth
import ./laws/SinceRefusesWord.bend as SinceRefusesWord
import ./laws/SourceDirsAreSafeAndDistinct.bend as SourceDirsAreSafeAndDistinct
import ./laws/SourceSplitIsOnePass.bend as SourceSplitIsOnePass
import ./laws/SubagentPromptByAgent.bend as SubagentPromptByAgent
import ./laws/ToolRecordsInlineOrPoint.bend as ToolRecordsInlineOrPoint
import ./laws/ToolResultIsPointer.bend as ToolResultIsPointer
import ./laws/TotalsRowOfTwo.bend as TotalsRowOfTwo
import ./laws/TotalSumsRows.bend as TotalSumsRows
import ./laws/TouchingSpanNotRecalled.bend as TouchingSpanNotRecalled
import ./laws/TruncatedLineIsNoRecord.bend as TruncatedLineIsNoRecord
import ./laws/UserLineAuthors.bend as UserLineAuthors
import ./laws/UserTextByNoah.bend as UserTextByNoah
import ./laws/Utf8ReadsAndReplaces.bend as Utf8ReadsAndReplaces
