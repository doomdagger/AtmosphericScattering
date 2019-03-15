Shader "Enviro/WeatherMap" {
	Properties {
		_Coverage ("Coverage", Range(0,1)) = 0.5
		_Tiling ("Tiling", Range(1,100)) = 10
	}
	SubShader {
		Tags { "RenderType"="Opaque" }
		LOD 200
		Pass {
		CGPROGRAM
	    #pragma vertex vert
        #pragma fragment frag
        #include "UnityCG.cginc"
        #include "EnviroNoiseCore.cginc"
		#pragma target 3.0

		sampler2D _MainTex;

		   struct VertexInput {
  				half4 vertex : POSITION;
 				float2 uv : TEXCOORD0;	
            };

            struct VertexOutput {
           		float4 position : SV_POSITION;
 				float2 uv : TEXCOORD0;
            };

            VertexOutput vert (VertexInput v) {
 			 	VertexOutput o;
 				o.position = UnityObjectToClipPos(v.vertex);				
 				o.uv = v.uv;
 				return o;
            }
 		
 			float _Coverage;
 			int _Tiling;

			float set_range(float value, float low, float high) {
							return saturate((value - low)/(high - low));
			}

			float remap(float value, float original_min, float original_max, float new_min, float new_max)
			{
  			  return new_min + saturate(((value - original_min) / (original_max - original_min)) * (new_max - new_min));
			}

 			float4 frag(VertexInput input) : SV_Target 
 			{
 				float3 sampling_pos1 = float3(input.uv, 0.0) * 2.0 * _Tiling;
				float3 sampling_pos2 = float3(input.uv, 0.0) * 2.0 * _Tiling;

				float perlin = perlin5oct(sampling_pos1);
				perlin = pow(perlin * 2, 1.0);
				perlin = perlin + _Coverage; 
				perlin = clamp(perlin, 0, 1);

				float perlin2 = perlin5oct(sampling_pos2);
				perlin2 = pow(perlin2*1.0, 1.0);
				perlin2 = perlin2 + _Coverage;
				perlin2 = clamp(perlin2, 0, 1);

				return float4(perlin, 0.1, perlin2, 0);
			}

	ENDCG
	}
	}
	FallBack "Diffuse"
}
