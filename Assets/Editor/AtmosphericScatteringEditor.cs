﻿using UnityEditor;
using UnityEngine;

[CustomEditor(typeof(AtmosphericScattering))]
class AtmosphericScatteringEditor : Editor
{
    private SerializedProperty generalSettingsFoldout;
    private SerializedProperty scatteringFoldout;
    private SerializedProperty sunFoldout;
    private SerializedProperty lightShaftsFoldout;
    private SerializedProperty ambientFoldout;
    private SerializedProperty dirLightFoldout;
    private SerializedProperty reflectionProbeFoldout;

    SerializedProperty RenderingMode;
    SerializedProperty ScatteringComputeShader;
	SerializedProperty FrostbiteReadShader;
    SerializedProperty FrostbiteWriteShader;
    SerializedProperty Sun;
    SerializedProperty RenderAtmosphericFog;
    SerializedProperty IncomingLight;
    SerializedProperty SunIlluminance;
    SerializedProperty RayleighScatterCoef;
    SerializedProperty MieScatterCoef;
    SerializedProperty MieG;
    // height fog begin
    SerializedProperty HFBetaRayleighScatterCoef;
    SerializedProperty HFBetaMieScatterCoef;
    SerializedProperty HFBetaAbsorptionScatterCoef;
    SerializedProperty HFMieAsymmetry;
    SerializedProperty HFScaleHeight;
    SerializedProperty HFAlbedoR;
    SerializedProperty HFAlbedoM;
    // height fog end
    // cloud begin
    SerializedProperty WindDirection;
    SerializedProperty WindSpeed;
    SerializedProperty SigmaScattering;
    SerializedProperty SigmaExtinction;
    SerializedProperty LowFreqUVScale;
    SerializedProperty HighFreqUVScale;
    // cloud end
    SerializedProperty RenderSun;
    SerializedProperty SunIntensity;
    SerializedProperty UpdateLightColor;
    SerializedProperty LightColorIntensity;
    SerializedProperty UpdateAmbientColor;
    SerializedProperty AmbientColorIntensity;
    SerializedProperty RenderLightShafts;
    SerializedProperty LightShaftQuality;
    SerializedProperty SampleCount;
    SerializedProperty ReflectionProbe;
    SerializedProperty ReflectionProbeResolution;
    SerializedProperty DistanceScale;

    string[] ResolutionNames = { "32", "64", "128", "256" };
    int[] Resolutions = { 32, 64, 128, 256 };

    int GetResolutionIndex(int resolution)
    {
        for (int i = 0; i < Resolutions.Length; ++i)
            if (Resolutions[i] == resolution)
                return i;
        return -1;
    }

    int GetResolution(int index)
    {
        return Resolutions[index];
    }

    void OnEnable()
    {
        generalSettingsFoldout = serializedObject.FindProperty("GeneralSettingsFoldout");
        scatteringFoldout = serializedObject.FindProperty("ScatteringFoldout");
        sunFoldout = serializedObject.FindProperty("SunFoldout");
        lightShaftsFoldout = serializedObject.FindProperty("LightShaftsFoldout");
        ambientFoldout = serializedObject.FindProperty("AmbientFoldout");
        dirLightFoldout = serializedObject.FindProperty("DirLightFoldout");
        reflectionProbeFoldout = serializedObject.FindProperty("ReflectionProbeFoldout");
        RenderingMode = serializedObject.FindProperty("RenderingMode");
        ScatteringComputeShader = serializedObject.FindProperty("ScatteringComputeShader");
		FrostbiteReadShader = serializedObject.FindProperty ("FrostbiteReadShader");
        FrostbiteWriteShader = serializedObject.FindProperty("FrostbiteWriteShader");
        Sun = serializedObject.FindProperty("Sun");
        RenderAtmosphericFog = serializedObject.FindProperty("RenderAtmosphericFog");
        IncomingLight = serializedObject.FindProperty("IncomingLight");
        SunIlluminance = serializedObject.FindProperty("SunIlluminance");
        RayleighScatterCoef = serializedObject.FindProperty("RayleighScatterCoef");
        MieScatterCoef = serializedObject.FindProperty("MieScatterCoef");
        MieG = serializedObject.FindProperty("MieG");

        HFBetaRayleighScatterCoef = serializedObject.FindProperty("HFBetaRayleighScatterCoef");
        HFBetaMieScatterCoef = serializedObject.FindProperty("HFBetaMieScatterCoef");
        HFBetaAbsorptionScatterCoef = serializedObject.FindProperty("HFBetaAbsorptionScatterCoef");
        HFMieAsymmetry = serializedObject.FindProperty("HFMieAsymmetry");
        HFScaleHeight = serializedObject.FindProperty("HFScaleHeight");
        HFAlbedoR = serializedObject.FindProperty("HFAlbedoR");
        HFAlbedoM = serializedObject.FindProperty("HFAlbedoM");

        WindDirection = serializedObject.FindProperty("WindDirection");
        WindSpeed = serializedObject.FindProperty("WindSpeed");
        SigmaScattering = serializedObject.FindProperty("SigmaScattering");
        SigmaExtinction = serializedObject.FindProperty("SigmaExtinction");
        LowFreqUVScale = serializedObject.FindProperty("LowFreqUVScale");
        HighFreqUVScale = serializedObject.FindProperty("HighFreqUVScale");

        RenderSun = serializedObject.FindProperty("RenderSun");
        SunIntensity = serializedObject.FindProperty("SunIntensity");
        UpdateLightColor = serializedObject.FindProperty("UpdateLightColor");
        LightColorIntensity = serializedObject.FindProperty("LightColorIntensity");
        UpdateAmbientColor = serializedObject.FindProperty("UpdateAmbientColor");
        AmbientColorIntensity = serializedObject.FindProperty("AmbientColorIntensity");
        RenderLightShafts = serializedObject.FindProperty("RenderLightShafts");
        LightShaftQuality = serializedObject.FindProperty("LightShaftQuality");
        SampleCount = serializedObject.FindProperty("SampleCount");
        ReflectionProbe = serializedObject.FindProperty("ReflectionProbe");
        ReflectionProbeResolution = serializedObject.FindProperty("ReflectionProbeResolution");
        DistanceScale = serializedObject.FindProperty("DistanceScale");
    }

    public override void OnInspectorGUI()
    {
        //DrawDefaultInspector();
        serializedObject.Update();

        AtmosphericScattering a = (AtmosphericScattering)target;

        GUIStyle s = new GUIStyle(EditorStyles.label);
        s.normal.textColor = Color.red;
        string errors = a.Validate().TrimEnd();
        if (errors != "")
            GUILayout.Label(errors, s);

        GUIStyle style = EditorStyles.foldout;
        FontStyle previousStyle = style.fontStyle;
        style.fontStyle = FontStyle.Bold;

        a.GeneralSettingsFoldout = EditorGUILayout.Foldout(a.GeneralSettingsFoldout, "General Settings", style);
        if (a.GeneralSettingsFoldout)
        {
            AtmosphericScattering.RenderMode rm = (AtmosphericScattering.RenderMode)EditorGUILayout.EnumPopup("Rendering Mode", (AtmosphericScattering.RenderMode)RenderingMode.enumValueIndex);
            RenderingMode.enumValueIndex = (int)rm;
            ScatteringComputeShader.objectReferenceValue = (ComputeShader)EditorGUILayout.ObjectField("Compute Shader", ScatteringComputeShader.objectReferenceValue, typeof(ComputeShader));
			FrostbiteReadShader.objectReferenceValue = (ComputeShader)EditorGUILayout.ObjectField ("Read Compute Shader", FrostbiteReadShader.objectReferenceValue, typeof(ComputeShader));
            FrostbiteWriteShader.objectReferenceValue = (ComputeShader)EditorGUILayout.ObjectField("Write Compute Shader", FrostbiteWriteShader.objectReferenceValue, typeof(ComputeShader));

            Sun.objectReferenceValue = (Light)EditorGUILayout.ObjectField("Sun", Sun.objectReferenceValue, typeof(Light));
        }

        a.ScatteringFoldout = EditorGUILayout.Foldout(a.ScatteringFoldout, "Atmospheric Scattering");
        if (a.ScatteringFoldout)
        {
            RenderAtmosphericFog.boolValue = EditorGUILayout.Toggle("Render Atm Fog", RenderAtmosphericFog.boolValue);
            IncomingLight.colorValue = EditorGUILayout.ColorField(new GUIContent("Incoming Light (*)"), IncomingLight.colorValue, false, false, true, new ColorPickerHDRConfig(0, 10, 0, 10));
            SunIlluminance.floatValue = EditorGUILayout.Slider("Sun Illuminance Ground Zenith", SunIlluminance.floatValue, 100000, 130000);
            RayleighScatterCoef.floatValue = EditorGUILayout.Slider("Rayleigh Coef (*)", RayleighScatterCoef.floatValue, 1, 10);
            MieScatterCoef.floatValue = EditorGUILayout.Slider("Mie Coef (*)", MieScatterCoef.floatValue, 1, 15);
            MieG.floatValue = EditorGUILayout.Slider("MieG", MieG.floatValue, 0, 0.999f);
            DistanceScale.floatValue = EditorGUILayout.FloatField("Distance Scale", DistanceScale.floatValue);

            HFBetaRayleighScatterCoef.floatValue = EditorGUILayout.Slider("HFBetaRayleighScatterCoef", HFBetaRayleighScatterCoef.floatValue, 0, 5000);
            HFBetaMieScatterCoef.floatValue = EditorGUILayout.Slider("HFBetaMieScatterCoef", HFBetaMieScatterCoef.floatValue, 0, 5000);
            HFBetaAbsorptionScatterCoef.floatValue = EditorGUILayout.Slider("HFBetaAbsorptionScatterCoef", HFBetaAbsorptionScatterCoef.floatValue, 0, 5000);
            HFMieAsymmetry.floatValue = EditorGUILayout.Slider("HFMieAsymmetry", HFMieAsymmetry.floatValue, 0, 0.999f);
            HFScaleHeight.floatValue = EditorGUILayout.FloatField("HFScaleHeight", HFScaleHeight.floatValue);
            HFAlbedoR.colorValue = EditorGUILayout.ColorField(new GUIContent("HFAlbedoR"), HFAlbedoR.colorValue, false, false, true, new ColorPickerHDRConfig(0, 10, 0, 10));
            HFAlbedoM.colorValue = EditorGUILayout.ColorField(new GUIContent("HFAlbedoM"), HFAlbedoM.colorValue, false, false, true, new ColorPickerHDRConfig(0, 10, 0, 10));

            WindDirection.vector3Value = EditorGUILayout.Vector3Field("Wind Direction", WindDirection.vector3Value);
            WindSpeed.floatValue = EditorGUILayout.Slider("Wind Speed", WindSpeed.floatValue, 0, 10);
            SigmaScattering.floatValue = EditorGUILayout.FloatField("Cloud Scattering", SigmaScattering.floatValue);
            SigmaExtinction.floatValue = EditorGUILayout.FloatField("Cloud Extinction", SigmaExtinction.floatValue);
            LowFreqUVScale.floatValue = EditorGUILayout.Slider("Low Freq UV Scale", LowFreqUVScale.floatValue, 1.0f, 10.0f);
            HighFreqUVScale.floatValue = EditorGUILayout.Slider("High Freq UV Scale", HighFreqUVScale.floatValue, 1.0f, 10.0f);

            GUILayout.Label("* - Change requires LookUp table update");
            if (GUILayout.Button("Update LookUp Tables") && a.IsInitialized())
                ((AtmosphericScattering)target).CalculateAtmosphere();
        }

        a.SunFoldout = EditorGUILayout.Foldout(a.SunFoldout, "Sun");
        if (a.SunFoldout)
        {
            RenderSun.boolValue = EditorGUILayout.Toggle("Render Sun", RenderSun.boolValue);
            SunIntensity.floatValue = EditorGUILayout.Slider("Sun Intensity", SunIntensity.floatValue, 0, 10);
        }

        a.DirLightFoldout = EditorGUILayout.Foldout(a.DirLightFoldout, "Directional Light");
        if (a.DirLightFoldout)
        {
            UpdateLightColor.boolValue = EditorGUILayout.Toggle("Update Color", UpdateLightColor.boolValue);
            LightColorIntensity.floatValue = EditorGUILayout.Slider("Intensity", LightColorIntensity.floatValue, 0, 4);
        }
        
        a.AmbientFoldout = EditorGUILayout.Foldout(a.AmbientFoldout, "Ambient Light");
        if (a.AmbientFoldout)
        {
            UpdateAmbientColor.boolValue = EditorGUILayout.Toggle("Update Color", UpdateAmbientColor.boolValue);
            AmbientColorIntensity.floatValue = EditorGUILayout.Slider("Intensity", AmbientColorIntensity.floatValue, 0, 4);
        }

        a.LightShaftsFoldout = EditorGUILayout.Foldout(a.LightShaftsFoldout, "Light Shafts");
        if (a.LightShaftsFoldout)
        {
            bool renderLightShafts = RenderLightShafts.boolValue;
            RenderLightShafts.boolValue = EditorGUILayout.Toggle("Enable Light Shafts", RenderLightShafts.boolValue);

            AtmosphericScattering.LightShaftsQuality quality = (AtmosphericScattering.LightShaftsQuality)LightShaftQuality.enumValueIndex;
            AtmosphericScattering.LightShaftsQuality currentQuality = (AtmosphericScattering.LightShaftsQuality)EditorGUILayout.EnumPopup("Quality", (AtmosphericScattering.LightShaftsQuality)LightShaftQuality.enumValueIndex);
            LightShaftQuality.enumValueIndex = (int)currentQuality;

            SampleCount.intValue = EditorGUILayout.IntSlider("Sample Count", SampleCount.intValue, 1, 64);
            //maxRayLengthProp.floatValue = EditorGUILayout.FloatField("Max Ray Length", maxRayLengthProp.floatValue);
        }

        a.ReflectionProbeFoldout = EditorGUILayout.Foldout(a.ReflectionProbeFoldout, "Reflection Probe");
        if (a.ReflectionProbeFoldout)
        {
            bool reflectionProbe = ReflectionProbe.boolValue;
            ReflectionProbe.boolValue = EditorGUILayout.Toggle("Enable Reflection Probe", ReflectionProbe.boolValue);

            int resolution = ReflectionProbeResolution.intValue;
            ReflectionProbeResolution.intValue = GetResolution(EditorGUILayout.Popup("Resolution", GetResolutionIndex(ReflectionProbeResolution.intValue), ResolutionNames));
        }

        serializedObject.ApplyModifiedProperties();
    }
}