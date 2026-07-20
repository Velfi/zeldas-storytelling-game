[CmdletBinding()]
param(
    [string]$EngineRoot = (Join-Path $PSScriptRoot "..\..\zelda-engine")
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$engine = (Resolve-Path $EngineRoot).Path
$build = Join-Path $root "build"
$vcpkg = if ($env:VCPKG_INSTALLATION_ROOT) { $env:VCPKG_INSTALLATION_ROOT } else { "C:\vcpkg" }
$installed = Join-Path $vcpkg "installed\x64-windows"
$clipper = Join-Path $root "third_party\clipper2\CPP\Clipper2Lib"

New-Item -ItemType Directory -Force $build | Out-Null

function Invoke-Native([scriptblock]$Command) {
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "Native command failed with exit code $LASTEXITCODE" }
}

Push-Location $root
try {
    $shaderBuild = Join-Path $build "shaders"
    New-Item -ItemType Directory -Force $shaderBuild | Out-Null
    Get-ChildItem "assets\shaders\precompiled\*.spv.b64" | ForEach-Object {
        $outputName = $_.Name -replace '\.b64$', ''
        $bytes = [Convert]::FromBase64String((Get-Content $_.FullName -Raw).Trim())
        [IO.File]::WriteAllBytes((Join-Path $shaderBuild $outputName), $bytes)
    }

    $joltSource = Join-Path $engine "third_party\JoltPhysics"
    if (-not (Test-Path (Join-Path $joltSource "Build\CMakeLists.txt"))) {
        Invoke-Native { git clone --depth 1 --branch v5.4.0 https://github.com/jrouwe/JoltPhysics.git $joltSource }
    }
    # The wrapper DLL uses MSVC's dynamic CRT (/MD). Jolt defaults to the static
    # CRT (/MT), which makes the two targets impossible to link together.
    Invoke-Native { cmake -S "$engine\third_party\jolt" -B "$engine\third_party\jolt\build-windows" -A x64 -DUSE_STATIC_MSVC_RUNTIME_LIBRARY=OFF }
    Invoke-Native { cmake --build "$engine\third_party\jolt\build-windows" --config Release --target zelda_physics }
    $physicsOutput = Join-Path $engine "third_party\jolt\Release"
    $physics = Join-Path $physicsOutput "zelda_physics.lib"
    if (-not (Test-Path $physics)) { throw "zelda_physics.lib was not produced at $physics" }
    Copy-Item $physics "$engine\third_party\jolt\zelda_physics.lib" -Force
    $physicsDll = Join-Path $physicsOutput "zelda_physics.dll"
    if (-not (Test-Path $physicsDll)) { throw "zelda_physics.dll was not produced at $physicsDll" }
    Copy-Item $physicsDll "$build\zelda_physics.dll" -Force

    Invoke-Native { cl /nologo /O2 /c "$engine\third_party\textshape\textshape.c" "/I$installed\include" "/I$installed\include\harfbuzz" "/I$installed\include\freetype2" "/Fo$engine\third_party\textshape\textshape.obj" }
    Invoke-Native { lib /nologo "/OUT:$engine\third_party\textshape\textshape.lib" "$engine\third_party\textshape\textshape.obj" }
    Copy-Item "$engine\third_party\textshape\textshape.lib" "third_party\textshape.lib" -Force

    Invoke-Native { cl /nologo /O2 /c third_party\tomlc17\tomlc17.c /Fothird_party\tomlc17\tomlc17.obj }
    Invoke-Native { lib /nologo /OUT:third_party\tomlc17\tomlc17.lib third_party\tomlc17\tomlc17.obj }
    Invoke-Native { cl /nologo /O2 /c third_party\stb_vorbis.c third_party\stb_vorbis_wrapper.c /Fothird_party\ }
    Invoke-Native { lib /nologo /OUT:third_party\stb_vorbis.lib third_party\stb_vorbis.obj third_party\stb_vorbis_wrapper.obj }
    Invoke-Native { cl /nologo /O2 /EHsc /std:c++17 "/I$clipper\include" /c third_party\wall_geom.cpp "$clipper\src\clipper.engine.cpp" "$clipper\src\clipper.offset.cpp" "$clipper\src\clipper.rectclip.cpp" /Fothird_party\ }
    Invoke-Native { lib /nologo /OUT:third_party\wall_geom.lib third_party\wall_geom.obj third_party\clipper.engine.obj third_party\clipper.offset.obj third_party\clipper.rectclip.obj }

    $iconResource = Join-Path $build "app-icon.res"
    Invoke-Native { rc /nologo "/fo$iconResource" tools\windows_app.rc }
    $linkFlags = "/LIBPATH:`"$installed\lib`" harfbuzz.lib freetype.lib brotlicommon.lib brotlidec.lib bz2.lib png.lib zlib.lib `"$iconResource`""
    Invoke-Native { odin build src "-collection:zelda_engine=$engine\packages" "-out:$build\zeldas-storytelling-game.exe" "-extra-linker-flags:$linkFlags" }
    Get-ChildItem "$installed\bin\*.dll" | Copy-Item -Destination $build -Force
} finally {
    Pop-Location
}
