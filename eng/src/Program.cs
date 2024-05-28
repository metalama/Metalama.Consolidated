// Copyright (c) SharpCrafters s.r.o. See the LICENSE.md file in the root directory of this repository root for details.

using BuildMetalamaConsolidated;
using PostSharp.Engineering.BuildTools;
using PostSharp.Engineering.BuildTools.Build;
using PostSharp.Engineering.BuildTools.Build.Model;
using PostSharp.Engineering.BuildTools.Build.Publishers;
using PostSharp.Engineering.BuildTools.Build.Publishers.Downloads;
using PostSharp.Engineering.BuildTools.Dependencies.Definitions;
using Spectre.Console.Cli;
using MetalamaDependencies = PostSharp.Engineering.BuildTools.Dependencies.Definitions.MetalamaDependencies.V2024_2;

var zipPackageName = "Metalama.$(PackageVersion).zip";
var versionPackageName = "Metalama.Framework";
var mainIndexName = "Index.xml";
var packageIndexName = $"Index.{versionPackageName}.xml";

var product = new Product( MetalamaDependencies.Consolidated )
{
    IsBundle = true,
    Solutions = [ new ConsolidatedBuildSolution( zipPackageName, versionPackageName ) ],
    Dependencies = [ DevelopmentDependencies.PostSharpEngineering ],
    Configurations = Product.DefaultConfigurations.WithValue(
        BuildConfiguration.Public,
        c => c with
        {
            PublicPublishers =
            [
                new DownloadPublisher(
                [
                    S3Helper.CreateConfiguration( zipPackageName, MetalamaDependencies.Consolidated.ProductFamily ),
                    S3Helper.CreateConfiguration( mainIndexName, MetalamaDependencies.Consolidated.ProductFamily ),
                    S3Helper.CreateConfiguration( packageIndexName, MetalamaDependencies.Consolidated.ProductFamily )
                ] ),
                new MergePublisher()
            ]
        } )
};

var commandApp = new CommandApp();
commandApp.AddProductCommands( product );

return commandApp.Run( args );