using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.ComponentModel;
using System.ComponentModel.DataAnnotations;
using System.Linq;
using QaaS.Framework.SDK.DataSourceObjects;
using QaaS.Framework.SDK.Hooks.Assertion;
using QaaS.Framework.SDK.Session.SessionDataObjects;

namespace ZappaDontCry.SelectedCandidates.Crawl4Ai.Assertions;

public sealed record HttpStatusBelow400Config
{
    [Description("Transaction output names to inspect.")]
    [Required]
    public string[] OutputNames { get; set; } = Array.Empty<string>();

    [Description("Exclusive maximum HTTP status code accepted by Docker curl -f semantics.")]
    [Range(100, 600)]
    public int MaximumExclusiveStatusCode { get; set; } = 400;
}

public sealed class HttpStatusBelow400 : BaseAssertion<HttpStatusBelow400Config>
{
    public override bool Assert(
        IImmutableList<SessionData> sessionDataList,
        IImmutableList<DataSource> dataSourceList)
    {
        if (Configuration is null)
        {
            AssertionMessage = "HttpStatusBelow400 configuration was not loaded.";
            return false;
        }

        var outputNames = (Configuration.OutputNames ?? Array.Empty<string>())
            .Where(name => !string.IsNullOrWhiteSpace(name))
            .Distinct(StringComparer.Ordinal)
            .ToImmutableArray();
        if (outputNames.Length == 0)
        {
            AssertionMessage = "At least one OutputNames value is required.";
            return false;
        }

        var failures = new List<string>();
        var observedCount = 0;
        foreach (var outputName in outputNames)
        {
            var observed = sessionDataList
                .SelectMany(session => session.GetOutputByName(outputName).Data)
                .ToImmutableList();

            if (observed.Count == 0)
            {
                failures.Add($"No output data observed for '{outputName}'.");
                continue;
            }

            observedCount += observed.Count;
            for (var index = 0; index < observed.Count; index++)
            {
                var statusCode = observed[index].MetaData?.Http?.StatusCode;
                if (statusCode is null)
                {
                    failures.Add($"Output '{outputName}' item {index} has no HTTP status metadata.");
                    continue;
                }

                if (statusCode >= Configuration.MaximumExclusiveStatusCode)
                {
                    failures.Add($"Output '{outputName}' item {index} status {statusCode} >= {Configuration.MaximumExclusiveStatusCode}.");
                }
            }
        }

        AssertionTrace = $"Observed {observedCount} output item(s); required status < {Configuration.MaximumExclusiveStatusCode}.";
        if (failures.Count > 0)
        {
            AssertionMessage = string.Join("; ", failures);
            return false;
        }

        AssertionMessage = $"All observed HTTP statuses were below {Configuration.MaximumExclusiveStatusCode}.";
        return true;
    }
}