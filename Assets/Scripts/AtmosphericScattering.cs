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
using UnityEditor;
using System.Collections;
using UnityEngine.Rendering;
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
	public ComputeShader FrostbiteComputeShader;
    public Light Sun;

	private RenderTexture _transmittanceLUT = null;
    private RenderTexture _gatherSumLUT = null;

    private Vector3 _skyboxLUTSize = new Vector3(32, 128, 32);

    private RenderTexture _skyboxLUT;
    private RenderTexture _skyboxLUT2;

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
    private readonly Vector4 DensityScale = new Vector4(7994.0f, 1200.0f, 0, 0);
    private readonly Vector4 RayleighSct = new Vector4(5.8f, 13.5f, 33.1f, 0.0f) * 0.000001f;
    private readonly Vector4 MieSct = new Vector4(5.0f, 5.0f, 5.0f, 0.0f) * 0.000001f;

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
        PrecomputeSkyboxLUT();
        //PrecomputeGatherSum();
        PrecomputeSkyboxLUT2();
    }

    /// <summary>
    /// 
    /// </summary>
    private void PrecomputeSkyboxLUT()
    {
        if (_skyboxLUT == null)
        {
            _skyboxLUT = new RenderTexture((int)_skyboxLUTSize.x, (int)_skyboxLUTSize.y, 0, RenderTextureFormat.ARGBHalf, RenderTextureReadWrite.Linear);
            _skyboxLUT.volumeDepth = (int)_skyboxLUTSize.z;
            _skyboxLUT.dimension = UnityEngine.Rendering.TextureDimension.Tex3D;
            _skyboxLUT.enableRandomWrite = true;
            _skyboxLUT.name = "SkyboxLUT";
            _skyboxLUT.Create();
        }

        int kernel = ScatteringComputeShader.FindKernel("SkyboxLUT");
        ScatteringComputeShader.SetTexture(kernel, "_SkyboxLUT", _skyboxLUT);
        UpdateCommonComputeShaderParameters(kernel);
        ScatteringComputeShader.Dispatch(kernel, (int)_skyboxLUTSize.x, (int)_skyboxLUTSize.y, (int)_skyboxLUTSize.z);

        SaveTextureAsKTX(_skyboxLUT, "skyboxlut");
    }

    private void PrecomputeSkyboxLUT2()
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

        int kernel = ScatteringComputeShader.FindKernel("MultipleScatterLUT");
        ScatteringComputeShader.SetTexture(kernel, "_SkyboxTex", _skyboxLUT);
        ScatteringComputeShader.SetTexture(kernel, "_SkyboxLUT2", _skyboxLUT2);
        UpdateCommonComputeShaderParameters(kernel);
        ScatteringComputeShader.Dispatch(kernel, (int)_skyboxLUTSize.x, (int)_skyboxLUTSize.y, (int)_skyboxLUTSize.z);

        SaveTextureAsKTX(_skyboxLUT2, "skyboxlut2");
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
    private void UpdateMaterialParameters(Material material)
	{
		material.SetFloat("_AtmosphereHeight", AtmosphereHeight);
		material.SetFloat("_PlanetRadius", PlanetRadius);
		material.SetVector("_DensityScaleHeight", DensityScale);

		material.SetVector("_ScatteringR", RayleighSct * RayleighScatterCoef);
		material.SetVector("_ScatteringM", MieSct * MieScatterCoef);
		material.SetVector("_ExtinctionR", RayleighSct * RayleighExtinctionCoef);
		material.SetVector("_ExtinctionM", MieSct * MieExtinctionCoef);

		material.SetFloat("_MieG", MieG);

		material.SetVector("_LightDir", new Vector4(Sun.transform.forward.x, Sun.transform.forward.y, Sun.transform.forward.z, 1.0f / (Sun.range * Sun.range)));
		material.SetVector("_LightColor", Sun.color * Sun.intensity);

		material.SetTexture("_SkyboxLUT", _skyboxLUT);
		material.SetTexture("_SkyboxLUT2", _skyboxLUT2);
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

    /// <summary>
    /// 
    /// </summary>
    public void OnPreRender()
    {
        UpdateSkyBoxParameters();
    }

	Texture2D ToTexture2D(RenderTexture rTex)
	{
		Texture2D tex = new Texture2D(rTex.width, rTex.height, TextureFormat.RGBAHalf, false);
		RenderTexture.active = rTex;
		tex.ReadPixels(new Rect(0, 0, rTex.width, rTex.height), 0, 0);
		tex.Apply();
		return tex;
	}

	/// <summary>
	/// 
	/// </summary>
	private void PrecomputeTransmittance()
	{
		if (_transmittanceLUT == null)
		{
			_transmittanceLUT = new RenderTexture(128, 32, 0, RenderTextureFormat.ARGBHalf, RenderTextureReadWrite.Linear);
			_transmittanceLUT.name = "TransmittanceLUT";
			_transmittanceLUT.filterMode = FilterMode.Bilinear;
			_transmittanceLUT.Create();
		}

		Texture nullTexture = null;
		Graphics.Blit(nullTexture, _transmittanceLUT, _frostbiteMat, 0);

        SaveTextureAsKTX(_transmittanceLUT, "transmittance");
	}

    /// <summary>
    /// 
    /// </summary>
    private void PrecomputeGatherSum()
    {
        if (_gatherSumLUT == null)
        {
            _gatherSumLUT = new RenderTexture(32, 32, 0, RenderTextureFormat.ARGBHalf, RenderTextureReadWrite.Linear);
            _gatherSumLUT.name = "GatherSumLUT";
            _gatherSumLUT.filterMode = FilterMode.Bilinear;
            _gatherSumLUT.Create();
        }

        _frostbiteMat.SetTexture("_SkyboxLUT", _skyboxLUT);

        Texture nullTexture = null;
        Graphics.Blit(nullTexture, _gatherSumLUT, _frostbiteMat, 1);

        SaveTextureAsKTX(_gatherSumLUT, "gathersum");
    }

    public void SaveTextureAsKTX(RenderTexture rtex, String name)
    {
        int texDepth = rtex.volumeDepth;
        int texWidth = rtex.width;
        int texHeight = rtex.height;
        int floatSize = sizeof(float);
        int channels = 4;

        int trueDepth;
        if (texDepth == 0)
        {
            trueDepth = 0;
            texDepth = 1;
        }
        else
        {
            trueDepth = texDepth;
        }

        int texSize = texWidth * texHeight * texDepth;

        ComputeBuffer buffer = new ComputeBuffer(texSize, floatSize * channels); // 4 bytes for float and 4 channels

        CBUtility.ReadFromRenderTexture(rtex, channels, buffer, FrostbiteComputeShader);

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
        UInt32 depth = (UInt32)trueDepth;
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

        for (int k = 0; k < texDepth; k++)
        {
            for (int j = 0; j < texHeight; j++)
                for (int i = 0; i < texWidth; i++)
                {
                    int startIndex = k * texWidth * texHeight * channels + j * texWidth * channels + i * channels;
                    writer.Write(Half.GetBytes((Half)data[startIndex]));
                    writer.Write(Half.GetBytes((Half)data[startIndex+1]));
                    writer.Write(Half.GetBytes((Half)data[startIndex+2]));
                    writer.Write(Half.GetBytes((Half)data[startIndex+3]));
                }
        }

        writer.Close();
        fs.Close();
        buffer.Release();
    }
}
