Shader "Unlit/BlinnPhong(URP)"
{
    Properties //开放给外界的属性
    {
        [Header(Textures)] //属性分组：纹理
        _BaseMap("Base Map", 2D) = "white" {} //主纹理贴图

        _Kd("漫反射系数", Color) = (1,1,1)
        _Ks("镜面反射系数", Color) = (1,1,1)
        _Ka("环境光系数", Color) = (1,1,1)
        _KsPow("镜面反射cos幂次", Float) = 200
    }
    SubShader //子着色器
    {
        Tags
        {
            "RenderPipeline" = "UniveralPipeline" //指定渲染管线
            "RenderType" = "Opaque" //指定渲染类型：不透明
        }

        HLSLINCLUDE //公共代码块开始
            //预处理指令、头文件、常量定义、函数定义
            #pragma multi_compile _MAIN_LIGHT_SHADOWS //主光源阴影
            #pragma multi_compile _MAIN_LIGHT_SHADOWS_CASCADE //主光源级联阴影
            #pragma multi_compile _MAIN_LIGHT_SHADOWS_SCREEN //主光源屏幕空间阴影

            #pragma multi_compile_fragment _LIGHT_LAYERS //光照层
            #pragma multi_compile_fragment _LIGHT_COOKIES //光照饼干
            #pragma multi_compile_fragment _SCREEN_SPACE_OCCLUSION //屏幕空间遮挡
            #pragma multi_compile_fragment _SHADOWS_SOFT //软阴影

            // 处理附加光源的阴影
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            // 处理附加光源的顶点光照（性能优化）
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX


            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl" //核心库
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl" //光照库


            CBUFFER_START(UnityPerMaterial) //材质常量缓冲区
                sampler2D _BaseMap;
                int _HalflambertPow;
                float3 _Kd;
                float3 _Ka;
                float3 _Ks;
                float _KsPow;
            CBUFFER_END
        
        ENDHLSL


        Pass //渲染通道
        {
            Name "Maple_UniversalForward" //通道名称
            Tags //标签
            {
                "LightMode" = "UniversalForward" //光照模型：前向渲染
            }

            HLSLPROGRAM
                #pragma vertex MapleVertexShader //声明顶点着色器入口
                #pragma fragment MapleFragmentShader //声明片段着色器入口    
            
                //顶点shader输入参数
                struct Attributes
                {
                    float4 positionOS : POSITION; //positionObejctSpace模型空间顶点坐标
                    float2 uv0 : TEXCOORD0; //第一套纹理坐标
                    float3 normalOS : NORMAL; //本地坐标法线
                };

                //由顶点着色器返回，传递给片元着色器的输入参数
                struct Varings
                {
                    float4 positionCS : SV_POSITION; //裁剪空间顶点坐标
                    float2 uv0 : TEXCOORD0; //第一套纹理坐标
                    float3 normalWS : TEXCOORD1; //世界空间法线
                    float3 positionWS : TEXCOORD2;
                };

                Varings MapleVertexShader(Attributes input) 
                {
                    Varings output;
                    
                    //顶点相关
                    VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz); //转换顶点空间
                    output.positionCS = vertexInput.positionCS; //拿到裁剪空间的坐标
                    output.positionWS = vertexInput.positionWS;
                    
                    //法线相关
                    VertexNormalInputs vertexNormalInput = GetVertexNormalInputs(input.normalOS); //转换法线坐标
                    output.normalWS = vertexNormalInput.normalWS; //拿到世界空间的法线坐标

                    //uv相关
                    output.uv0 = input.uv0;

                    return output; //返回屏幕空间位置
                }

                //计算光照Ld、Ls
                half3 CalculateLight(Light light, Varings input, half3 col)
                {
                    //光源方向
                    half3 l = light.direction;
                    //法线
                    half3 n = normalize(input.normalWS);
                    
                    half3 Ld = _Kd * col * light.distanceAttenuation * max(0, dot(n, l));

                    //观察方向
                    half3 v = normalize(GetCameraPositionWS() - input.positionWS);

                    //半程向量
                    half3 h = normalize(v + l);
                
                    half3 Ls = _Ks * col * light.distanceAttenuation * pow(max(0, dot(n, h)), _KsPow);

                    return Ld + Ls;
                }

                //返回rgba
                half4 MapleFragmentShader(Varings input) : SV_TARGET
                {
                    Light light = GetMainLight();

                    half3 col = tex2D(_BaseMap, input.uv0).xyz; //采样纹理贴图

                    half3 LsPlusLd = CalculateLight(light, input, col);

                    //环境光
                    half3 La = UNITY_LIGHTMODEL_AMBIENT.rgb * col * _Ka;

                    half3 finalCol = LsPlusLd + La;

                    //计算点光源
                    uint additionalLightsCount = GetAdditionalLightsCount();
                    for (uint lightIndex = 0u; lightIndex < additionalLightsCount; lightIndex++)
                    {
                        Light addLight = GetAdditionalLight(lightIndex, input.positionWS);
                        
                        //计算这个光源的贡献
                        half3 addLightColor = CalculateLight(addLight, input, col);
                        
                        //将附加光源的贡献累加
                        finalCol += addLightColor * addLight.shadowAttenuation;
                    }


                    //阴影只影响漫反射和镜面反射，不影响环境光
                    return half4(finalCol, 1.0);
                }

            ENDHLSL
        }
    }
}
