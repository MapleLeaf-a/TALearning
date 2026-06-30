Shader "Unlit/BlinnPhong(URP)"
{
    Properties
    {
        [Header(Textures)]
        _BaseMap("Base Map", 2D) = "white" {}

        _Kd("漫反射系数", Color) = (1,1,1)
        _Ks("镜面反射系数", Color) = (1,1,1)
        _Ka("环境光系数", Color) = (1,1,1)
        _KsPow("镜面反射cos幂次", Float) = 200

        [Header(PCSS Shadows)]
        [Space]
        [Toggle(_PCSS_ON)] _PCSS("启用 PCSS 软阴影", Float) = 0
        _LightSize("光源大小", Range(0.0, 0.5)) = 0.05
        _BlockerSearchRange("遮挡搜索范围(纹素)", Range(0, 50)) = 20
        _BlockerSamples("遮挡搜索采样数(每边)", Range(1, 10)) = 5
        _PCFSamples("PCF滤波采样数(每边)", Range(1, 10)) = 5
    }
    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniveralPipeline"
            "RenderType" = "Opaque"
        }

        HLSLINCLUDE
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS

            #pragma multi_compile_fragment _LIGHT_LAYERS
            #pragma multi_compile_fragment _LIGHT_COOKIES
            #pragma multi_compile_fragment _SCREEN_SPACE_OCCLUSION
            #pragma multi_compile_fragment _SHADOWS_SOFT

            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            CBUFFER_START(UnityPerMaterial)
                sampler2D _BaseMap;
                float3 _Kd;
                float3 _Ka;
                float3 _Ks;
                float _KsPow;

                float _LightSize;
                float _BlockerSearchRange;
                int _BlockerSamples;
                int _PCFSamples;
            CBUFFER_END

        ENDHLSL


        Pass
        {
            Name "Maple_UniversalForward"
            Tags
            {
                "LightMode" = "UniversalForward"
            }

            HLSLPROGRAM
                #pragma vertex MapleVertexShader
                #pragma fragment MapleFragmentShader
                #pragma shader_feature_local _PCSS_ON

                struct Attributes
                {
                    float4 positionOS : POSITION;
                    float2 uv0 : TEXCOORD0;
                    float3 normalOS : NORMAL;
                };

                struct Varings
                {
                    float4 positionCS : SV_POSITION;
                    float2 uv0 : TEXCOORD0;
                    float3 normalWS : TEXCOORD1;
                    float3 positionWS : TEXCOORD2;
                };

                Varings MapleVertexShader(Attributes input)
                {
                    Varings output;

                    VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                    output.positionCS = vertexInput.positionCS;
                    output.positionWS = vertexInput.positionWS;

                    VertexNormalInputs vertexNormalInput = GetVertexNormalInputs(input.normalOS);
                    output.normalWS = vertexNormalInput.normalWS;

                    output.uv0 = input.uv0;

                    return output;
                }

                // ============================================================
                // PCSS — GAMES202 三步算法
                // ============================================================

                // 读取阴影贴图原始深度（使用内置 sampler_PointClamp，无需声明）
                float SampleShadowMapRawDepth(float2 uv)
                {
                    return SAMPLE_TEXTURE2D_LOD(_MainLightShadowmapTexture, sampler_PointClamp, uv, 0).r;
                }

                // 生成一个随屏幕坐标变化的伪随机角度（确定性，无闪烁）
                float GetRotationAngle(float2 uv)
                {
                    return dot(uv, float2(12.9898, 78.233)) * 43758.5453 % 1.0;
                }

                // Step 1: Blocker Search
                float FindBlockerDepth(float2 shadowUV, float d_receiver)
                {
                    float2 texelSize = _MainLightShadowmapSize.xy;
                    float searchRadius = _BlockerSearchRange * texelSize.x;

                    // 生成旋转角度（基于 UV，避免跨像素闪烁）
                    float angle = GetRotationAngle(shadowUV * 100.0);
                    float cosA = cos(angle);
                    float sinA = sin(angle);

                    float avgBlockerDepth = 0;
                    float blockerCount = 0;

                    int halfSamples = (_BlockerSamples - 1) / 2;
                    for (int x = -halfSamples; x <= halfSamples; x++)
                    {
                        for (int y = -halfSamples; y <= halfSamples; y++)
                        {
                            // 基础偏移量（网格坐标）
                            float2 baseOffset = float2(x, y) * searchRadius;
                            // 旋转偏移
                            float2 rotatedOffset = float2(
                                baseOffset.x * cosA - baseOffset.y * sinA,
                                baseOffset.x * sinA + baseOffset.y * cosA
                            );
                            float sampleDepth = SampleShadowMapRawDepth(shadowUV + rotatedOffset);

                            if (sampleDepth < d_receiver - 0.001)
                            {
                                avgBlockerDepth += sampleDepth;
                                blockerCount += 1.0;
                            }
                        }
                    }

                    if (blockerCount > 0.0)
                        return avgBlockerDepth / blockerCount;
                    else
                        return 1.0;
                }

                // Step 2: Penumbra Estimation
                // 返回值为阴影贴图纹素数（texels）
                float EstimatePenumbraWidth(float d_receiver, float d_blocker)
                {
                    float ratio = (d_receiver - d_blocker) / max(d_blocker, 0.001);
                    // _LightSize: 光源在阴影贴图中占的纹素比例（0.05 = 5%的阴影贴图宽度）
                    return ratio * _LightSize * _MainLightShadowmapSize.z;
                }

                // Step 3: 可变大小 PCF
                // filterRadiusTexels: 滤波半径，单位为阴影贴图纹素
                float PCSS_PCF(float2 shadowUV, float d_receiver, float filterRadiusTexels)
                {
                    float2 texelSize = _MainLightShadowmapSize.xy;
                    float stepUV = filterRadiusTexels * texelSize.x; // 转换为 UV 单位

                    // 生成旋转角度（不同于 Blocker 的角度，+1.0 偏移避免完全一致）
                    float angle = GetRotationAngle(shadowUV * 100.0 + 1.0);
                    float cosA = cos(angle);
                    float sinA = sin(angle);

                    float shadowSum = 0;
                    float sampleCount = 0;

                    int halfSamples = (_PCFSamples - 1) / 2;
                    for (int x = -halfSamples; x <= halfSamples; x++)
                    {
                        for (int y = -halfSamples; y <= halfSamples; y++)
                        {
                            float2 baseOffset = float2(x, y) * stepUV;
                            float2 rotatedOffset = float2(
                                baseOffset.x * cosA - baseOffset.y * sinA,
                                baseOffset.x * sinA + baseOffset.y * cosA
                            );
                            float s = SAMPLE_TEXTURE2D_SHADOW(
                                _MainLightShadowmapTexture, sampler_LinearClampCompare,
                                float3(shadowUV + rotatedOffset, d_receiver));
                            shadowSum += s;
                            sampleCount += 1.0;
                        }
                    }

                    return shadowSum / sampleCount;
                }

                

                // PCSS 主函数
                float ComputePCSS(float4 shadowCoord)
                {
                    float2 uv = shadowCoord.xy;

                    // 超出阴影贴图范围的区域 = 无阴影（完全照亮）
                    if (any(uv < 0.0) || any(uv > 1.0))
                        return 1.0;

                    // 从阴影贴图采样深度作为接收深度（加偏置避免自遮挡）
                    float d_recv = SampleShadowMapRawDepth(uv) + 0.001;

                    float d_blocker = FindBlockerDepth(uv, d_recv);
                    if (d_blocker >= 1.0 - 0.001)
                        return 1.0;

                    float w = EstimatePenumbraWidth(d_recv, d_blocker);
                    return PCSS_PCF(uv, d_recv, w);
                }

                // ============================================================
                // 光照计算
                // ============================================================
                half3 CalculateLight(Light light, Varings input, half3 col, half shadowAttenuation)
                {
                    half3 l = light.direction;
                    half3 n = normalize(input.normalWS);

                    half NdotL = max(0, dot(n, l));
                    half3 Ld = _Kd * col * light.distanceAttenuation * NdotL * shadowAttenuation;

                    half3 v = normalize(GetCameraPositionWS() - input.positionWS);
                    half3 h = normalize(v + l);
                    half3 Ls = _Ks * col * light.distanceAttenuation * pow(max(0, dot(n, h)), _KsPow) * shadowAttenuation;

                    return Ld + Ls;
                }

                half4 MapleFragmentShader(Varings input) : SV_TARGET
                {
                    half3 col = tex2D(_BaseMap, input.uv0).xyz;

                    // ---------- 主光源 ----------
                    float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);

                    half shadowAttenuation;
                    #if _PCSS_ON
                        // ====== PCSS 模式 ======
                        float pcssShadow = ComputePCSS(shadowCoord);
                        float shadowStrength = _MainLightShadowParams.x;
                        shadowAttenuation = lerp(1.0 - shadowStrength, 1.0, pcssShadow);

                        // 调试: 直接看阴影贴图原始深度
                        // return float4(SampleShadowMapRawDepth(shadowCoord.xy).xxx, 1.0);
                    #else
                        // ====== 标准 URP 阴影 ======
                        shadowAttenuation = MainLightRealtimeShadow(shadowCoord);
                    #endif

                    half3 finalCol = CalculateLight(GetMainLight(), input, col, shadowAttenuation);

                    // 环境光
                    half3 La = UNITY_LIGHTMODEL_AMBIENT.rgb * col * _Ka;
                    finalCol += La;

                    // ---------- 附加光源 ----------
                    uint additionalLightsCount = GetAdditionalLightsCount();
                    for (uint lightIndex = 0u; lightIndex < additionalLightsCount; lightIndex++)
                    {
                        Light addLight = GetAdditionalLight(lightIndex, input.positionWS);
                        half3 addLightColor = CalculateLight(addLight, input, col, addLight.shadowAttenuation);
                        finalCol += addLightColor;
                    }

                    return half4(finalCol, 1.0);
                }

            ENDHLSL
        }

        // ============================================================
        // ShadowCaster Pass — 让物体能被渲染到阴影贴图中
        // 没有这个 Pass，物体无法投射阴影！
        // ============================================================
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Off

            HLSLPROGRAM
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
            };

            float3 _LightDirection;
            float3 _LightPosition;

            Varyings ShadowPassVertex(Attributes input)
            {
                Varyings output;
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, _LightDirection));
                output.positionCS = positionCS;
                return output;
            }

            half4 ShadowPassFragment(Varyings input) : SV_TARGET
            {
                return 0;
            }
            ENDHLSL
        }
    }
}
