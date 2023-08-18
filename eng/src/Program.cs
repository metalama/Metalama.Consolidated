// Copyright (c) SharpCrafters s.r.o. See the LICENSE.md file in the root directory of this repository root for details.

using PostSharp.Engineering.BuildTools;
using PostSharp.Engineering.BuildTools.Build.Model;
using PostSharp.Engineering.BuildTools.Dependencies.Definitions;
using Spectre.Console.Cli;
using MetalamaDependencies = PostSharp.Engineering.BuildTools.Dependencies.Definitions.MetalamaDependencies.V2023_2;

var product = new Product( MetalamaDependencies.Consolidated )
{
    IsBundle = true,
    Dependencies = new[] { DevelopmentDependencies.PostSharpEngineering }
};

var commandApp = new CommandApp();
commandApp.AddProductCommands( product );

return commandApp.Run( args );