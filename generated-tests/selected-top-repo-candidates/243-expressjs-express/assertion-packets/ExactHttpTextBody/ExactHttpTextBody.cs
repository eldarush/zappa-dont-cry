using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.ComponentModel;
using System.ComponentModel.DataAnnotations;
using System.Linq;
using System.Text;
using QaaS.Framework.SDK.DataSourceObjects;
using QaaS.Framework.SDK.Extensions;
using QaaS.Framework.SDK.Hooks.Assertion;
using QaaS.Framework.SDK.Session.SessionDataObjects;

namespace ZappaDontCry.SelectedCandidates.Express.Assertions;

public sealed record ExactHttpTextBodyConfig
{
    [Description("Transaction output name to inspect.")]
    [Required]
    public string OutputName { get; set; } = string.Empty;

    [Description("Exact expected response body text.")]
    [Required]
    public string ExpectedText { get; set; } = string.Empty;

    [Description("Encoding name used to decode the response Body byte array.")]
    [DefaultValue("utf-8")]
    public string EncodingName { get; set; } = "utf-8";
}

public sealed class ExactHttpTextBody : BaseAssertion<ExactHttpTextBodyConfig>
{
    public override bool Assert(
        IImmutableList<SessionData> sessionDataList,
        IImmutableList<DataSource> dataSourceList)
    {
        if (Configuration is null)
        {
            AssertionMessage = "ExactHttpTextBody configuration was not loaded.";
            return false;
        }

        if (string.IsNullOrWhiteSpace(Configuration.OutputName))
        {
            AssertionMessage = "OutputName is required.";
            return false;
        }

        Encoding encoding;
        try
        {
            encoding = Encoding.GetEncoding(
                string.IsNullOrWhiteSpace(Configuration.EncodingName)
                    ? "utf-8"
                    : Configuration.EncodingName);
        }
        catch (ArgumentException exception)
        {
            AssertionMessage = $"Encoding '{Configuration.EncodingName}' is not supported: {exception.Message}";
            return false;
        }

        var observed = sessionDataList
            .SelectMany(session => session.GetOutputByName(Configuration.OutputName).Data)
            .ToImmutableList();

        if (observed.Count == 0)
        {
            AssertionMessage = $"No output data observed for '{Configuration.OutputName}'.";
            return false;
        }

        var failures = new List<string>();
        for (var index = 0; index < observed.Count; index++)
        {
            var item = observed[index];
            if (item.Body is not byte[] body)
            {
                failures.Add($"item {index} body was {item.Body?.GetType().Name ?? "null"}, expected byte[].");
                continue;
            }

            var actualText = encoding.GetString(body);
            if (!string.Equals(actualText, Configuration.ExpectedText, StringComparison.Ordinal))
            {
                failures.Add($"item {index} body mismatch: expected {Configuration.ExpectedText.Length} chars, actual {actualText.Length} chars.");
            }
        }

        AssertionTrace = $"Observed {observed.Count} output item(s) for '{Configuration.OutputName}'.";
        if (failures.Count > 0)
        {
            AssertionMessage = string.Join("; ", failures);
            return false;
        }

        AssertionMessage = $"All observed bodies exactly matched {Configuration.ExpectedText.Length} expected character(s).";
        return true;
    }
}