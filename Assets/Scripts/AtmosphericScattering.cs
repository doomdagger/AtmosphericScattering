//  Copyright(c) 2016, Michal Skalsky
//  All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without modification,
//  are permitted provided that the following conditions are met:
//
//  1. Redistributions of source code must retain the above copyright notice,
//     this list of conditions and the following disclaimer.
//
//  2. Redistributions in binary form must reproduce the above copyright notice,
//     this list of conditions and the following disclaimer in the documentation
//     and/or other materials provided with the distribution.
//
//  3. Neither the name of the copyright holder nor the names of its contributors
//     may be used to endorse or promote products derived from this software without
//     specific prior written permission.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
//  EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
//  OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.IN NO EVENT
//  SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
//  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
//  OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
//  HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR
//  TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
//  EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.



using UnityEngine;
using System.Collections;
using System;
using System.Text;
using System.IO;
using Common.Unity.Drawing;

[RequireComponent(typeof(Camera))]
public class AtmosphericScattering : MonoBehaviour
{
    public enum RenderMode
    {
        Reference,
        Optimized
    }

    public enum LightShaftsQuality
    {
        High,
        Medium
    }

    public RenderMode RenderingMode = RenderMode.Optimized;
    public LightShaftsQuality LightShaftQuality = LightShaftsQuality.Medium;
    public ComputeShader ScatteringComputeShader;
	public ComputeShader FrostbiteReadShader;
    public ComputeShader FrostbiteWriteShader;
    public Light Sun;

	private RenderTexture _transmittanceLUT = null;
    private RenderTexture _gatherSumLUT = null;
    private RenderTexture _gatherSumLUT2 = null;

    private RenderTexture _sunlightLUT; // for now, same size with transmittance texture
    private RenderTexture _skylightLUT;

    private Vector3 _skyboxLUTSize = new Vector3(32, 128, 32);
    private Vector2 _transmitLUTSize = new Vector2(32, 128);
    private Vector2 _gatherSumLUTSize = new Vector2(32, 32);

    private float[] _skyboxData = null;

    private Vector3 _inscatteringLUTSize = new Vector3(32, 32, 16);
    private RenderTexture _inscatteringLUT;
    private RenderTexture _extinctionLUT;

    private RenderTexture _skyboxLUT;
    private RenderTexture _skyboxLUT2;
    private RenderTexture _skyboxLUTSingle;
    private int _gatherSumCount = 1;
    private int _skyboxCount = 1;

	private Material _frostbiteMat;

    private Camera _camera;

    [Range(1, 64)]
    public int SampleCount = 16;
    public float MaxRayLength = 400;

    [ColorUsage(false, true, 0, 10, 0, 10)]
    public Color IncomingLight = new Color(4, 4, 4, 4);
    [Range(0, 10.0f)]
    public float RayleighScatterCoef = 1;
    [Range(0, 10.0f)]
    public float RayleighExtinctionCoef = 1;
    [Range(0, 10.0f)]
    public float MieScatterCoef = 1;
    [Range(0, 10.0f)]
    public float MieExtinctionCoef = 1;
    [Range(0.0f, 0.999f)]
    public float MieG = 0.76f;
    public float DistanceScale = 1;
    [Range(1, 5000.0f)]
    public float HFBetaRayleighScatterCoef = 1;
    [Range(1, 5000.0f)]
    public float HFBetaMieScatterCoef = 1;
    [Range(1, 5000.0f)]
    public float HFBetaAbsorptionScatterCoef = 1;
    [Range(0.0f, 0.999f)]
    public float HFMieAsymmetry = 0.402f;
    public float HFScaleHeight = 1200;
    [ColorUsage(false, true, 0, 10, 0, 10)]
    public Color HFAlbedoR = new Color(1, 1, 1, 1);
    [ColorUsage(false, true, 0, 10, 0, 10)]
    public Color HFAlbedoM = new Color(1, 1, 1, 1);

    public bool UpdateLightColor = true;
    [Range(0.5f, 3.0f)]
    public float LightColorIntensity = 1.0f;
    public bool UpdateAmbientColor = true;
    [Range(0.5f, 3.0f)]
    public float AmbientColorIntensity = 1.0f;

    public bool RenderSun = true;
    public float SunIntensity = 1;
    public bool RenderLightShafts = false;
    public bool RenderAtmosphericFog = true;
    public bool ReflectionProbe = true;
    public int ReflectionProbeResolution = 128;

#if UNITY_EDITOR
    public bool GeneralSettingsFoldout = true;
    public bool ScatteringFoldout = true;
    public bool SunFoldout = false;
    public bool LightShaftsFoldout = true;
    public bool AmbientFoldout = false;
    public bool DirLightFoldout = false;
    public bool ReflectionProbeFoldout = false;
    private StringBuilder _stringBuilder = new StringBuilder();
#endif

    private const float AtmosphereHeight = 80000.0f;
    private const float PlanetRadius = 6371000.0f;
    private readonly Vector4 DensityScale = new Vector4(8000.0f, 1200.0f, 8000.0f, 0);
    private readonly Vector4 RayleighSct = new Vector4(5.8f, 13.5f, 33.1f, 0.0f) * 0.000001f;
    private readonly Vector4 MieSct = new Vector4(5.0f, 5.0f, 5.0f, 0.0f) * 0.000001f;
    private readonly Vector4 OzoneExt = new Vector4(3.426f, 8.298f, 0.356f, 0.0f) * 0.000001f;

    private readonly Vector3 HFBetaRayleighScatter = new Vector3(5.8f, 13.5f, 33.1f) * 0.000001f;
    private readonly float HFBetaMieScatter = 2.0f * 0.000001f;
    private readonly float HFBetaAbsorptionScatter = 1.0f * 0.000001f;

    private Vector4[] _FrustumCorners = new Vector4[4];
    public float SunIlluminance = 120000;

    private bool AerialPerspPersisted = false;

    /// <summary>
    /// 
    /// </summary>
    void Start()
    {   
		Shader shader = Shader.Find("Hidden/FrostbiteAtmosphere");
		if (shader == null)
			throw new Exception("Critical Error: \"Hidden/FrostbiteAtmosphere\" shader is missing. Make sure it is included in \"Always Included Shaders\" in ProjectSettings/Graphics.");
		_frostbiteMat = new Material(shader);

        _camera = GetComponent<Camera>();

        CalculateAtmosphere();

        InitializeAerialPerspLUTs();
    }

#if UNITY_EDITOR
    /// <summary>
    /// 
    /// </summary>
    public string Validate()
    {
        _stringBuilder.Length = 0;
        if (RenderSettings.skybox == null)
            _stringBuilder.AppendLine("! RenderSettings.skybox is null");
        else if (RenderSettings.skybox.shader.name != "Skybox/AtmosphericScattering")
            _stringBuilder.AppendLine("! RenderSettings.skybox material is using wrong shader");
        if (ScatteringComputeShader == null)
            _stringBuilder.AppendLine("! Atmospheric Scattering compute shader is missing (General Settings)");
        if (Sun == null)
            _stringBuilder.AppendLine("! Sun (main directional light) isn't set (General Settings)");
        return _stringBuilder.ToString();
    }
#endif

    public bool IsInitialized()
    {
        return _frostbiteMat != null;
    }

    public void CalculateAtmosphere()
    {
        UpdateMaterialParameters(_frostbiteMat);

        PrecomputeTransmittance();
        PrecomputeSkyboxLUT(); // gen lut 1k
        PrecomputeGatherSum(); // gather sum 1k
        PrecomputeGatherSumAllTogether();
        PrecomputeSkyboxAlltogether();
        PrecomputeMultipleSkyboxLUT(); // use sum 1k to gen lut 2k
        PrecomputeGatherSum(); // gather sum 2k
        PrecomputeGatherSumAllTogether(); // add sum 2k into 1k
        PrecomputeSkyboxAlltogether();
        PrecomputeMultipleSkyboxLUT(); // use sum 2k to gen lut 3k
        PrecomputeGatherSum(); // gather sum 3k
        PrecomputeGatherSumAllTogether(); // add sum 3k into 1k
        PrecomputeSkyboxAlltogether();
        CreateFinalSkyboxLUT();
        PrecomputeSkyAndSunlightRadiance();
    }

    private void InitializeAerialPerspLUTs()
    {
        _inscatteringLUT = new RenderTexture((int)_inscatteringLUTSize.x, (int)_inscatteringLUTSize.y, 0, RenderTextureFormat.ARGBHalf, RenderTextureReadWrite.Linear);
        _inscatteringLUT.volumeDepth = (int)_inscatteringLUTSize.z;
        _inscatteringLUT.dimension = UnityEngine.Rendering.TextureDimension.Tex3D;
        _inscatteringLUT.enableRandomWrite = true;
        _inscatteringLUT.name = "InscatteringLUT";
        _inscatteringLUT.Create();

        _extinctionLUT = new RenderTexture((int)_inscatteringLUTSize.x, (int)_inscatteringLUTSize.y, 0, RenderTextureFormat.ARGBHalf, RenderTextureReadWrite.Linear);
        _extinctionLUT.volumeDepth = (int)_inscatteringLUTSize.z;
        _extinctionLUT.dimension = UnityEngine.Rendering.TextureDimension.Tex3D;
        _extinctionLUT.enableRandomWrite = true;
        _extinctionLUT.name = "ExtinctionLUT";
        _extinctionLUT.Create();
    }

    /// <summary>
    /// 
    /// </summary>
    private void PrecomputeSkyboxLUT()
    {
        if (_skyboxLUT2 == null)
        {
            _skyboxLUT2 = new RenderTexture((int)_skyboxLUTSize.x, (int)_skyboxLUTSize.y, 0, RenderTextureFormat.ARGBHalf, RenderTextureReadWrite.Linear);
            _skyboxLUT2.volumeDepth = (int)_skyboxLUTSize.z;
            _skyboxLUT2.dimension = UnityEngine.Rendering.TextureDimension.Tex3D;
            _skyboxLUT2.enableRandomWrite = true;
            _skyboxLUT2.name = "SkyboxLUT2";
            _skyboxLUT2.Create();
        }

        if (_skyboxLUTSingle == null)
        {
            _skyboxLUTSingle = new RenderTexture((int)_skyboxLUTSize.x, (int)_skyboxLUTSize.y, 0, RenderTextureFormat.ARGBHalf, RenderTextureReadWrite.Linear);
            _skyboxLUTSingle.volumeDepth = (int)_skyboxLUTSize.z;
            _skyboxLUTSingle.dimension = UnityEngine.Rendering.TextureDimension.Tex3D;
            _skyboxLUTSingle.enableRandomWrite = true;
            _skyboxLUTSingle.name = "SkyboxLUTSingle";
            _skyboxLUTSingle.Create();
        }

        int kernel = ScatteringComputeShader.FindKernel("SkyboxLUT");
        ScatteringComputeShader.SetTexture(kernel, "_SkyboxLUT2", _skyboxLUT2);
        ScatteringComputeShader.SetTexture(kernel, "_SkyboxLUTSingle", _skyboxLUTSingle);
        UpdateCommonComputeShaderParameters(kernel);
        ScatteringComputeShader.Dispatch(kernel, (int)_skyboxLUTSize.x, (int)_skyboxLUTSize.y, (int)_skyboxLUTSize.z);

        SaveTextureAsKTX(_skyboxLUT2, "skyboxlut"+_skyboxCount++, true);
        SaveTextureAsKTX(_skyboxLUTSingle, "skyboxlutsingle", true);
    }

    private void PrecomputeMultipleSkyboxLUT()
    {
        int kernel = ScatteringComputeShader.FindKernel("MultipleScatterLUT");

        ScatteringComputeShader.SetTexture(kernel, "_GatherSumLUT2", _gatherSumLUT2); // gather sum of previous order
        ScatteringComputeShader.SetTexture(kernel, "_SkyboxLUT2", _skyboxLUT2); // current write to
        UpdateCommonComputeShaderParameters(kernel);
        ScatteringComputeShader.Dispatch(kernel, (int)_skyboxLUTSize.x, (int)_skyboxLUTSize.y, (int)_skyboxLUTSize.z);

        SaveTextureAsKTX(_skyboxLUT2, "skyboxlut"+_skyboxCount++, true);
    }

    /// <summary>
	/// 
	/// </summary>
	private void PrecomputeTransmittance()
    {
        if (_transmittanceLUT == null)
        {
            _transmittanceLUT = new RenderTexture((int)_transmitLUTSize.x, (int)_transmitLUTSize.y, 0, RenderTextureFormat.ARGBHalf, RenderTextureReadWrite.Linear);
            _transmittanceLUT.name = "TransmittanceLUT";
            _transmittanceLUT.filterMode = FilterMode.Bilinear;
            _transmittanceLUT.Create();
        }

        Texture nullTexture = null;
        Graphics.Blit(nullTexture, _transmittanceLUT, _frostbiteMat, 0);

        SaveTextureAsKTX(_transmittanceLUT, "transmittance");
    }

    private void PrecomputeSkyboxAlltogether()
    {
        int texDepth = (int)_skyboxLUTSize.z;
        int texWidth = (int)_skyboxLUTSize.x;
        int texHeight = (int)_skyboxLUTSize.y;
        int floatSize = sizeof(float);
        int channels = 4;
        int texSize = texWidth * texHeight * texDepth;
        bool firstTime = false;

        if (_skyboxData == null)
        {
            firstTime = true;
            _skyboxData = new float[texSize * channels];
        }

        ComputeBuffer buffer = new ComputeBuffer(texSize, floatSize * channels); // 4 bytes for float and 4 channels
        CBUtility.ReadFromRenderTexture(_skyboxLUT2, channels, buffer, FrostbiteReadShader);
        float[] data = new float[texSize * channels];
        buffer.GetData(data);

        if (firstTime)
        {
            for (int i = 0; i < _skyboxData.Length; ++i)
                _skyboxData[i] = data[i];
        }
        else
        {
            for (int i = 0; i < _skyboxData.Length; ++i)
                _skyboxData[i] += data[i];
        }

        buffer.Release();
    }

    private void CreateFinalSkyboxLUT()
    {
        int texDepth = (int)_skyboxLUTSize.z;
        int texWidth = (int)_skyboxLUTSize.x;
        int texHeight = (int)_skyboxLUTSize.y;
        int floatSize = sizeof(float);
        int channels = 4;
        int texSize = texWidth * texHeight * texDepth;

        if (_skyboxLUT == null)
        {
            _skyboxLUT = new RenderTexture((int)_skyboxLUTSize.x, (int)_skyboxLUTSize.y, 0, RenderTextureFormat.ARGBHalf, RenderTextureReadWrite.Linear);
            _skyboxLUT.volumeDepth = (int)_skyboxLUTSize.z;
            _skyboxLUT.dimension = UnityEngine.Rendering.TextureDimension.Tex3D;
            _skyboxLUT.enableRandomWrite = true;
            _skyboxLUT.name = "SkyboxLUT";
            _skyboxLUT.Create();
        }

        ComputeBuffer buffer = new ComputeBuffer(texSize, floatSize * channels); // 4 bytes for float and 4 channels
        buffer.SetData(_skyboxData);
        CBUtility.WriteIntoRenderTexture(_skyboxLUT, channels, buffer, FrostbiteWriteShader);

        buffer.Release();
        SaveTextureAsKTX(_skyboxLUT, "skyboxlut", true);
    }

    /// <summary>
    /// 
    /// </summary>
    private void PrecomputeGatherSum()
    {
        if (_gatherSumLUT2 == null)
        {
            _gatherSumLUT2 = new RenderTexture((int)_gatherSumLUTSize.x, (int)_gatherSumLUTSize.y, 0, RenderTextureFormat.ARGBHalf, RenderTextureReadWrite.Linear);
            _gatherSumLUT2.name = "GatherSumLUT2";
            _gatherSumLUT2.filterMode = FilterMode.Bilinear;
            _gatherSumLUT2.Create();
        }

        _frostbiteMat.SetTexture("_SkyboxLUT2", _skyboxLUT2);

        Texture nullTexture = null;
        Graphics.Blit(nullTexture, _gatherSumLUT2, _frostbiteMat, 1);

        SaveTextureAsKTX(_gatherSumLUT2, "gathersum" + _gatherSumCount++);
    }

    /// <summary>
    /// 
    /// </summary>
    private void PrecomputeGatherSumAllTogether()
    {
        bool firstTime = false;
        if (_gatherSumLUT == null)
        {
            _gatherSumLUT = new RenderTexture((int)_gatherSumLUTSize.x, (int)_gatherSumLUTSize.y, 0, RenderTextureFormat.ARGBHalf, RenderTextureReadWrite.Linear);
            _gatherSumLUT.name = "GatherSumLUT";
            _gatherSumLUT.filterMode = FilterMode.Bilinear;
            _gatherSumLUT.Create();

            firstTime = true;
        }

        Texture2D korder = ToTexture2D(_gatherSumLUT2);

        if (firstTime)
        {
            Graphics.Blit(korder, _gatherSumLUT);
        }
        else
        {
            Texture2D sum = ToTexture2D(_gatherSumLUT);

            Color[] sumColors = sum.GetPixels();
            Color[] korderColors = korder.GetPixels();

            for (int i = 0; i < sumColors.Length; ++i)
            {
                sumColors[i] += korderColors[i];
            }

            sum.SetPixels(sumColors);
            sum.Apply();
            Graphics.Blit(sum, _gatherSumLUT);
        }

        SaveTextureAsKTX(_gatherSumLUT, "gathersum");
    }

    private void PrecomputeSkyAndSunlightRadiance()
    {
        if (_skylightLUT == null)
        {
            _skylightLUT = new RenderTexture((int)_transmitLUTSize.x, (int)_transmitLUTSize.y, 0, RenderTextureFormat.ARGBHalf, RenderTextureReadWrite.Linear);
            _skylightLUT.name = "SkylightLUT";
            _skylightLUT.filterMode = FilterMode.Bilinear;
            _skylightLUT.Create();
        }
        if (_sunlightLUT == null)
        {
            _sunlightLUT = new RenderTexture((int)_transmitLUTSize.x, (int)_transmitLUTSize.y, 0, RenderTextureFormat.ARGBHalf, RenderTextureReadWrite.Linear);
            _sunlightLUT.name = "SunlightLUT";
            _sunlightLUT.filterMode = FilterMode.Bilinear;
            _sunlightLUT.Create();
        }

        // draw sky light lut
        _frostbiteMat.SetTexture("_SkyboxLUT", _skyboxLUT);
        _frostbiteMat.SetTexture("_TransmittanceLUT", _transmittanceLUT);

        Texture nullTexture = null;
        Graphics.Blit(nullTexture, _skylightLUT, _frostbiteMat, 3);
        SaveTextureAsKTX(_skylightLUT, "skylightlut");

        // draw sun light lut
        nullTexture = null;
        Graphics.Blit(nullTexture, _sunlightLUT, _frostbiteMat, 4);
        SaveTextureAsKTX(_sunlightLUT, "sunlightlut");
    }

    /// <summary>
    /// 
    /// </summary>
    private void UpdateCommonComputeShaderParameters(int kernel)
    {
        ScatteringComputeShader.SetTexture(kernel, "_TransmittanceLUT", _transmittanceLUT);

        ScatteringComputeShader.SetFloat("_AtmosphereHeight", AtmosphereHeight);
        ScatteringComputeShader.SetFloat("_PlanetRadius", PlanetRadius);
        ScatteringComputeShader.SetVector("_DensityScaleHeight", DensityScale);

        ScatteringComputeShader.SetVector("_ScatteringR", RayleighSct * RayleighScatterCoef);
        ScatteringComputeShader.SetVector("_ScatteringM", MieSct * MieScatterCoef);
        ScatteringComputeShader.SetVector("_ExtinctionR", RayleighSct * RayleighExtinctionCoef);
        ScatteringComputeShader.SetVector("_ExtinctionM", MieSct * MieExtinctionCoef);

        ScatteringComputeShader.SetVector("_LightColor", Sun.color * Sun.intensity);
        ScatteringComputeShader.SetFloat("_MieG", MieG);

        ScatteringComputeShader.SetVector("_ScatterLUTSize", _skyboxLUTSize);
        ScatteringComputeShader.SetVector("_TransmittanceLUTSize", _transmitLUTSize);
        ScatteringComputeShader.SetVector("_GatherSumLUTSize", _gatherSumLUTSize);
    }

    /// <summary>
    /// 
    /// </summary>
    private void UpdateMaterialParameters(Material material)
    {
        material.SetTexture("_TransmittanceLUT", _transmittanceLUT);

        material.SetFloat("_AtmosphereHeight", AtmosphereHeight);
        material.SetFloat("_PlanetRadius", PlanetRadius);
        material.SetVector("_DensityScaleHeight", DensityScale);

        material.SetVector("_ScatteringR", RayleighSct * RayleighScatterCoef);
        material.SetVector("_ScatteringM", MieSct * MieScatterCoef);
        material.SetVector("_ExtinctionR", RayleighSct * RayleighExtinctionCoef);
        material.SetVector("_ExtinctionM", MieSct * MieExtinctionCoef);
        material.SetVector("_ExtinctionO", OzoneExt);

        material.SetFloat("_MieG", MieG);

        material.SetVector("_LightDir", new Vector4(Sun.transform.forward.x, Sun.transform.forward.y, Sun.transform.forward.z, 1.0f / (Sun.range * Sun.range)));
        material.SetVector("_LightIrradiance", Sun.color * Sun.intensity);
        material.SetFloat("_SunIlluminance", SunIlluminance);

        material.SetTexture("_SkyboxLUT", _skyboxLUT);
        material.SetTexture("_SkyboxLUT2", _skyboxLUT2);
        material.SetTexture("_SkyboxLUTSingle", _skyboxLUTSingle);

        material.SetVector("_ScatterLUTSize", _skyboxLUTSize);
        material.SetVector("_TransmittanceLUTSize", _transmitLUTSize);
        material.SetVector("_GatherSumLUTSize", _gatherSumLUTSize);

        // height fog
        material.SetVector("_HFBetaRs", HFBetaRayleighScatter * HFBetaRayleighScatterCoef);
        material.SetFloat("_HFBetaMs", HFBetaMieScatter * HFBetaMieScatterCoef);
        material.SetFloat("_HFBetaMa", HFBetaAbsorptionScatter * HFBetaAbsorptionScatterCoef);
        material.SetFloat("_HFMieAsymmetry", HFMieAsymmetry);
        material.SetFloat("_HFScaleHeight", HFScaleHeight);
        material.SetVector("_HFAlbedoR", HFAlbedoR);
        material.SetVector("_HFAlbedoM", HFAlbedoM);
        material.SetTexture("_SunlightLUT", _sunlightLUT);
        material.SetTexture("_SkylightLUT", _skylightLUT);
    }

    /// <summary>
    /// 
    /// </summary>
    private void UpdateSkyBoxParameters()
    {
        if (RenderSettings.skybox != null)
        {
            RenderSettings.skybox.SetVector("_CameraPos", _camera.transform.position);
            UpdateMaterialParameters(RenderSettings.skybox);
            if (RenderingMode == RenderMode.Reference)
                RenderSettings.skybox.EnableKeyword("ATMOSPHERE_REFERENCE");
            else
                RenderSettings.skybox.DisableKeyword("ATMOSPHERE_REFERENCE");
        }
    }

    private void UpdateAerialPerspParameters()
    {
        // bottom left
        _FrustumCorners[0] = _camera.ViewportToWorldPoint(new Vector3(0, 0, _camera.farClipPlane));
        // top left
        _FrustumCorners[1] = _camera.ViewportToWorldPoint(new Vector3(0, 1, _camera.farClipPlane));
        // top right
        _FrustumCorners[2] = _camera.ViewportToWorldPoint(new Vector3(1, 1, _camera.farClipPlane));
        // bottom right
        _FrustumCorners[3] = _camera.ViewportToWorldPoint(new Vector3(1, 0, _camera.farClipPlane));

        // Compute Shader
        int kernel = ScatteringComputeShader.FindKernel("AerialPerspLUT");

        ScatteringComputeShader.SetTexture(kernel, "_InscatteringLUT", _inscatteringLUT);
        ScatteringComputeShader.SetTexture(kernel, "_ExtinctionLUT", _extinctionLUT);
        ScatteringComputeShader.SetTexture(kernel, "_GatherSumLUT", _gatherSumLUT);

        ScatteringComputeShader.SetVector("_InscatteringLUTSize", _inscatteringLUTSize);

        ScatteringComputeShader.SetVector("_BottomLeftCorner", _FrustumCorners[0]);
        ScatteringComputeShader.SetVector("_TopLeftCorner", _FrustumCorners[1]);
        ScatteringComputeShader.SetVector("_TopRightCorner", _FrustumCorners[2]);
        ScatteringComputeShader.SetVector("_BottomRightCorner", _FrustumCorners[3]);

        ScatteringComputeShader.SetVector("_CameraPos", transform.position);
        ScatteringComputeShader.SetVector("_LightDir", Sun.transform.forward);
        ScatteringComputeShader.SetVector("_LightColor", Sun.color * Sun.intensity);

        UpdateCommonComputeShaderParameters(kernel);

        ScatteringComputeShader.Dispatch(kernel, (int)_inscatteringLUTSize.x, (int)_inscatteringLUTSize.y, 1);

        if (!AerialPerspPersisted)
        {
            SaveTextureAsKTX(_inscatteringLUT, "apinscatter", true);
            SaveTextureAsKTX(_extinctionLUT, "apextinction", true);
            AerialPerspPersisted = true;
        }

        // Postproess Shader
        _frostbiteMat.SetTexture("_InscatteringLUT", _inscatteringLUT);
        _frostbiteMat.SetTexture("_ExtinctionLUT", _extinctionLUT);
        _frostbiteMat.SetVectorArray("_FrustumCorners", _FrustumCorners);
        UpdateMaterialParameters(_frostbiteMat);
    } 

    /// <summary>
    /// 
    /// </summary>
    public void OnDestroy()
    {
		Destroy (_frostbiteMat);
    }

       /// <summary>
    /// 
    /// </summary>
    void Update()
    {

    }

    /// <summary>
    /// 
    /// </summary>
    public void OnPreRender()
    {
        UpdateSkyBoxParameters();
        UpdateAerialPerspParameters();
    }

    /// <summary>
    /// 
    /// </summary>
    [ImageEffectOpaque]
    public void OnRenderImage(RenderTexture source, RenderTexture destination)
    {
        _frostbiteMat.SetTexture("_Background", source);

        Texture nullTexture = null;
        Graphics.Blit(nullTexture, destination, _frostbiteMat, 2);
    }

    Texture2D ToTexture2D(RenderTexture rTex)
	{
		Texture2D tex = new Texture2D(rTex.width, rTex.height, TextureFormat.RGBAHalf, false);
		RenderTexture.active = rTex;
		tex.ReadPixels(new Rect(0, 0, rTex.width, rTex.height), 0, 0);
		tex.Apply();
		return tex;
	}

    public void SaveTextureAsKTX(RenderTexture rtex, String name, bool tile3D = false)
    {
        int texDepth = rtex.volumeDepth;
        int texWidth = rtex.width;
        int texHeight = rtex.height;
        int floatSize = sizeof(float);
        int channels = 4;

        bool tileEnabled = tile3D && texDepth > 1;
        if (tileEnabled)
        {
            texWidth *= texDepth;
            texDepth = 1;
        }


        int texSize = texWidth * texHeight * texDepth;

        ComputeBuffer buffer = new ComputeBuffer(texSize, floatSize * channels); // 4 bytes for float and 4 channels

        CBUtility.ReadFromRenderTexture(rtex, channels, buffer, FrostbiteReadShader);

        float[] data = new float[texSize * channels];

        buffer.GetData(data);

        Byte[] header = {
            0xAB, 0x4B, 0x54, 0x58, // first four bytes of Byte[12] identifier
			0x20, 0x31, 0x31, 0xBB, // next four bytes of Byte[12] identifier
			0x0D, 0x0A, 0x1A, 0x0A, // final four bytes of Byte[12] identifier
			0x01, 0x02, 0x03, 0x04, // Byte[4] endianess (Big endian in this case)
		};

        FileStream fs = new FileStream("Assets/Textures/"+name+".ktx", FileMode.OpenOrCreate);
        BinaryWriter writer = new BinaryWriter(fs);
        writer.Write(header);

        UInt32 glType = 0x140B; // HALF
        UInt32 glTypeSize = 2; // 2 bytes
        UInt32 glFormat = 0x1908; // RGBA
        UInt32 glInterformat = 0x881A; // RGBA FLOAT16
        UInt32 glBaseInternalFormat = 0x1908; // RGBA
        UInt32 width = (UInt32)texWidth;
        UInt32 height = (UInt32)texHeight;
        UInt32 depth = (UInt32)(texDepth == 1 ? 0 : texDepth);
        UInt32 numOfArrElem = 0;
        UInt32 numOfFace = 1;
        UInt32 numOfMip = 1;
        UInt32 bytesOfKeyVal = 0;

        writer.Write(glType);
        writer.Write(glTypeSize);
        writer.Write(glFormat);
        writer.Write(glInterformat);
        writer.Write(glBaseInternalFormat);
        writer.Write(width);
        writer.Write(height);
        writer.Write(depth);
        writer.Write(numOfArrElem);
        writer.Write(numOfFace);
        writer.Write(numOfMip);
        writer.Write(bytesOfKeyVal);

        UInt32 imageSize = (UInt32)(texSize * channels * glTypeSize);
        writer.Write(imageSize);

        if (tileEnabled)
        {
            for (int j = 0; j < rtex.height; j++)
                for (int k = 0; k < rtex.volumeDepth; k++)
                    for (int i = 0; i < rtex.width; i++)
                    {
                        int startIndex = k * rtex.width * rtex.height * channels + j * rtex.width * channels + i * channels;
                        writer.Write(Half.GetBytes((Half)data[startIndex]));
                        writer.Write(Half.GetBytes((Half)data[startIndex + 1]));
                        writer.Write(Half.GetBytes((Half)data[startIndex + 2]));
                        writer.Write(Half.GetBytes((Half)data[startIndex + 3]));
                    }
        }
        else
        {
            for (int i = 0; i < data.Length; ++i)
            {
                writer.Write(Half.GetBytes((Half)data[i]));
            }
        }

        writer.Close();
        fs.Close();
        buffer.Release();
    }
}
