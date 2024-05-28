// Copyright (c) SharpCrafters s.r.o. See the LICENSE.md file in the root directory of this repository root for details.

using Amazon;
using PostSharp.Engineering.BuildTools.Build.Model;
using PostSharp.Engineering.BuildTools.Dependencies.Model;
using PostSharp.Engineering.BuildTools.S3.Publishers;

namespace BuildMetalamaConsolidated;

internal static class S3Helper
{
    public static S3PublisherConfiguration CreateConfiguration( ParametricString fileName, ProductFamily family )
        => new(
            fileName,
            RegionEndpoint.EUWest1,
            "download-sharpcrafters-com",
            $"metalama/metalama-{family.Version}/v$(PackageVersion)/{fileName}");
}