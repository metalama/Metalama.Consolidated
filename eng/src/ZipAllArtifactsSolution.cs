// Copyright (c) SharpCrafters s.r.o. See the LICENSE.md file in the root directory of this repository root for details.

using PostSharp.Engineering.BuildTools.Build;
using PostSharp.Engineering.BuildTools.Build.Model;
using PostSharp.Engineering.BuildTools.Build.Publishing.Downloads;
using System;
using System.IO;
using System.IO.Compression;
using System.Linq;

namespace BuildMetalamaConsolidated;

internal class ZipAllArtifactsSolution : Solution
{
    private readonly string _versionPackageName;
    private readonly ParametricString _zipPackageFileName;

    public ZipAllArtifactsSolution( ParametricString zipPackageFileName, string versionPackageName ) : base( null! )
    {
        this._zipPackageFileName = zipPackageFileName;
        this._versionPackageName = versionPackageName;
    }

    public override bool Build( BuildContext context, BuildSettings settings ) => throw new NotSupportedException();

    public override bool Pack( BuildContext context, BuildSettings settings )
    {
        var artifactsDirectory =
            Path.Combine(
                context.RepoDirectory,
                settings.BuildConfiguration switch
                {
                    BuildConfiguration.Public => context.Product.PublicArtifactsDirectory,
                    _ => context.Product.GetPrivateArtifactsRelativeDirectory( settings.BuildConfiguration )
                } );

        var dependenciesDirectory = Path.Combine( context.RepoDirectory, "dependencies" );

        var packageExtensions = new[] { ".nupkg", ".snupkg" };

        var packages = Directory.EnumerateFiles( dependenciesDirectory, "*.*", SearchOption.AllDirectories )
            .Where( p => packageExtensions.Contains( Path.GetExtension( p ) ) )
            .ToArray();

        if ( !BuildArguments.TryReadFromAutoUpdatedVersionsFile( context, settings.BuildConfiguration, out var buildArguments ) )
        {
            return false;
        }

        var buildInfo = BuildArguments.ReadFromArtifactManifest( context, settings.BuildConfiguration );
        var zipFileName = this._zipPackageFileName.ToString( buildInfo );
        var zipFilePath = Path.Combine( artifactsDirectory, zipFileName );

        context.Console.WriteMessage( $"Creating '{zipFilePath}' archive." );

        if ( !Directory.Exists( artifactsDirectory ) )
        {
            Directory.CreateDirectory( artifactsDirectory );
        }

        using ( var zipFile = ZipFile.Open( zipFilePath, ZipArchiveMode.Create ) )
        {
            foreach ( var package in packages )
            {
                var packageName = Path.GetFileName( package );
                
                if ( packageName.StartsWith( "Metalama.", StringComparison.Ordinal ) || packageName.StartsWith( "Flashtrace", StringComparison.Ordinal ) )
                {
                    context.Console.WriteMessage( $"Adding '{packageName}' package." );
                    zipFile.CreateEntryFromFile( package, Path.GetFileName( package ) );
                }
            }
        }

        context.Console.WriteMessage( "Creating index files." );

        var downloadsFolder = DownloadFolder.Create( context, buildArguments );

        var packageDownloadFile = DownloadFile.Create(
            zipFilePath,
            "All NuGet packages in a zip file.",
            null );

        var mainIndex = new DownloadIndex( downloadsFolder, null, true );
        mainIndex.Write( artifactsDirectory );

        var packageIndex = new DownloadIndex( downloadsFolder.WithFiles( [packageDownloadFile] ), zipFileName, false );
        packageIndex.Write( artifactsDirectory );

        return true;
    }

    public override bool Test( BuildContext context, BuildSettings settings ) => true;

    public override bool Restore( BuildContext context, BuildSettings settings ) => true;
}