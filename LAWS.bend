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
# main.bend's pure parts live in src/cli.bend. What the shell does is trusted
# in each module's header, and its defs and types no law can import carry
# `# noqa: L001` with the reason; tests/smoke.sh runs it end
# to end on records given as JSON lines, and tests/live.sh, run by hand, runs the reader pool against live readers.
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
# laws/RecordsInputChanges.bend (records given as JSON lines),
# laws/LiveKeepsLastVersion.bend (current records: changes and removals;
# laws/ChangedRecordKeepsItsPlace.bend says where a changed one is kept),
# laws/RequestAdmitsOnlyLabels.bend (readers and ask;
# laws/BestRankedArePrinted.bend says which of the labels they name are
# printed, laws/AskingsArePassedOver.bend which are passed over first as
# earlier askings of the question),
# laws/ToolQueryIsCliQuery.bend (the server's tool calls),
# laws/TelemetryLineOfARun.bend (telemetry),
# laws/CliNamesItsCommands.bend (the command line, src/cli.bend), and
# laws/HitsCountRecalled.bend and laws/CoverageAddsOverExcerpts.bend (the
# eval).
#
# The other law files are closed examples, each one law named for what it
# checks and with no prose (laws/BlankLinesSeparateParagraphs.bend,
# laws/ShardJsonRoundTrips.bend, ...), and
# laws/ShardLabelsNumberParagraphs.bend, a quantified law no guarantee
# claims. They promise nothing beyond the equality each states.
import Base
import ./laws/AskingsArePassedOver.bend as AskingsArePassedOver
import ./laws/AuthorKeepsNamedAuthors.bend as AuthorKeepsNamedAuthors
import ./laws/BareDotIsNoSource.bend as BareDotIsNoSource
import ./laws/BestRankedArePrinted.bend as BestRankedArePrinted
import ./laws/BlankLinesSeparateParagraphs.bend as BlankLinesSeparateParagraphs
import ./laws/BookPacksIntoShards.bend as BookPacksIntoShards
import ./laws/ChangedRecordKeepsItsPlace.bend as ChangedRecordKeepsItsPlace
import ./laws/ChatSourceDirName.bend as ChatSourceDirName
import ./laws/CliNamesItsCommands.bend as CliNamesItsCommands
import ./laws/CoverageAddsOverExcerpts.bend as CoverageAddsOverExcerpts
import ./laws/CutReplyFails.bend as CutReplyFails
import ./laws/DepthLimitsARankedRun.bend as DepthLimitsARankedRun
import ./laws/EmptyAnswerIsOk.bend as EmptyAnswerIsOk
import ./laws/EmptyIdLineIsNoRecord.bend as EmptyIdLineIsNoRecord
import ./laws/EmptyParasLineIsNoRecord.bend as EmptyParasLineIsNoRecord
import ./laws/EveryShardIsRead.bend as EveryShardIsRead
import ./laws/ExcerptsFitBudget.bend as ExcerptsFitBudget
import ./laws/ExcerptsRenderAsText.bend as ExcerptsRenderAsText
import ./laws/ExtendResumesPack.bend as ExtendResumesPack
import ./laws/FailedReadsListed.bend as FailedReadsListed
import ./laws/FilterHitsChosenSources.bend as FilterHitsChosenSources
import ./laws/FilterParseSplitsAndTrims.bend as FilterParseSplitsAndTrims
import ./laws/FilterRefusesCoveredSelectors.bend as FilterRefusesCoveredSelectors
import ./laws/FinalFeedNotInParagraph.bend as FinalFeedNotInParagraph
import ./laws/FooterNamesFailedShards.bend as FooterNamesFailedShards
import ./laws/FreezingIsStable.bend as FreezingIsStable
import ./laws/FrozenShardsFitCap.bend as FrozenShardsFitCap
import ./laws/FullTailStaysOpen.bend as FullTailStaysOpen
import ./laws/HitsCountRecalled.bend as HitsCountRecalled
import ./laws/IngestKeepsRecordsThatFit.bend as IngestKeepsRecordsThatFit
import ./laws/LeadingBlankLinesDropped.bend as LeadingBlankLinesDropped
import ./laws/LiveKeepsLastVersion.bend as LiveKeepsLastVersion
import ./laws/LongParaLineIsNoRecord.bend as LongParaLineIsNoRecord
import ./laws/MakeNeedsAParagraph.bend as MakeNeedsAParagraph
import ./laws/MedianAndMax.bend as MedianAndMax
import ./laws/MedianAndMaxOfTimes.bend as MedianAndMaxOfTimes
import ./laws/MergeJoinsRecordAcrossShards.bend as MergeJoinsRecordAcrossShards
import ./laws/MergeOrdersByTime.bend as MergeOrdersByTime
import ./laws/NextBestAreInPages.bend as NextBestAreInPages
import ./laws/NoAuthorChangesNothing.bend as NoAuthorChangesNothing
import ./laws/Non200Fails.bend as Non200Fails
import ./laws/NonJsonReplyFails.bend as NonJsonReplyFails
import ./laws/NoParasLineIsNoRecord.bend as NoParasLineIsNoRecord
import ./laws/NoSinceChangesNothing.bend as NoSinceChangesNothing
import ./laws/NoticeAnswerTellsReads.bend as NoticeAnswerTellsReads
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
import ./laws/RatioRoundsDown.bend as RatioRoundsDown
import ./laws/RecalledMeansOverlap.bend as RecalledMeansOverlap
import ./laws/RecordHeaderAndSize.bend as RecordHeaderAndSize
import ./laws/RecordLineRoundTrips.bend as RecordLineRoundTrips
import ./laws/RecordsInputChanges.bend as RecordsInputChanges
import ./laws/RecordsSplitOnlyWhenTooBig.bend as RecordsSplitOnlyWhenTooBig
import ./laws/ReplyIsOkOrFailed.bend as ReplyIsOkOrFailed
import ./laws/ReplyReadsLabelsAndTimings.bend as ReplyReadsLabelsAndTimings
import ./laws/ReplyReadsRanks.bend as ReplyReadsRanks
import ./laws/RankedReadNamesShard.bend as RankedReadNamesShard
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
import ./laws/ShardsGiveBackRecords.bend as ShardsGiveBackRecords
import ./laws/ShowFindsRecordAndParagraphs.bend as ShowFindsRecordAndParagraphs
import ./laws/ShowReadsOneSource.bend as ShowReadsOneSource
import ./laws/ShowReadsRunFiles.bend as ShowReadsRunFiles
import ./laws/ShowRunsCommandOutput.bend as ShowRunsCommandOutput
import ./laws/ShowWantsIdAndParagraph.bend as ShowWantsIdAndParagraph
import ./laws/SinceDateIsMidnight.bend as SinceDateIsMidnight
import ./laws/SinceDropsOldExcerpts.bend as SinceDropsOldExcerpts
import ./laws/SinceKeepsFullTime.bend as SinceKeepsFullTime
import ./laws/SinceKeepsRecentShards.bend as SinceKeepsRecentShards
import ./laws/SinceRefusesNoSeconds.bend as SinceRefusesNoSeconds
import ./laws/SinceRefusesShortMonth.bend as SinceRefusesShortMonth
import ./laws/SinceRefusesWord.bend as SinceRefusesWord
import ./laws/SourceDirsAreSafeAndDistinct.bend as SourceDirsAreSafeAndDistinct
import ./laws/SourceShardsHoldCurrentRecords.bend as SourceShardsHoldCurrentRecords
import ./laws/SourcesCountsEachSource.bend as SourcesCountsEachSource
import ./laws/SourceSplitIsOnePass.bend as SourceSplitIsOnePass
import ./laws/TelemetryLineOfARun.bend as TelemetryLineOfARun
import ./laws/ToolQueryIsCliQuery.bend as ToolQueryIsCliQuery
import ./laws/TotalsRowOfTwo.bend as TotalsRowOfTwo
import ./laws/TotalSumsRows.bend as TotalSumsRows
import ./laws/TouchingSpanNotRecalled.bend as TouchingSpanNotRecalled
import ./laws/TruncatedLineIsNoRecord.bend as TruncatedLineIsNoRecord
