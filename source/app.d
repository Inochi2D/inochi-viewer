/*
    Copyright © 2020, Inochi2D Project
    Distributed under the 2-Clause BSD License, see LICENSE file.
    
    Authors: Luna Nielsen
*/
import std.stdio;
import bindbc.glfw;
import bindbc.opengl;
import inochi2d;
import std.string;
import std.process;
import nulib.math : clamp;
import inochi2d.core.math;
import gl;

GLFWwindow* window;
void main(string[] args)
{
	if (args.length == 1) {
		writeln("No model specified!");
		return;
	}

	// Loads GLFW
	loadGLFW();
	glfwInit();

	glfwWindowHint (GLFW_CONTEXT_VERSION_MAJOR, 4);
	glfwWindowHint (GLFW_CONTEXT_VERSION_MINOR, 5);
	glfwWindowHint (GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
	glfwWindowHint (GLFW_TRANSPARENT_FRAMEBUFFER, environment.get("TRANSPARENT") == "1" ? GLFW_TRUE : GLFW_FALSE);
	glfwWindowHint (GL_FRAMEBUFFER_ATTACHMENT_ALPHA_SIZE, 8);

	window = glfwCreateWindow(1024, 1024, "Inochi2D Viewer".toStringz, null, null);
	glfwMakeContextCurrent(window);
	loadOpenGL();


	// Prepare viewport
	int sceneWidth, sceneHeight;
	glfwGetFramebufferSize(window, &sceneWidth, &sceneHeight);

	Puppet[] puppets;
	float size = (args.length-1)*2048;
	float halfway = size/2;

	foreach(i; 1..args.length) {
		puppets ~= inLoadPuppet(args[i]);
		puppets[i-1].root.localTransform.translation.x = (((i)*2048)-halfway)-1024;

		import std.array : join;
		auto meta = puppets[i-1].meta;
		writefln("---Model Info---\n%s by %s & %s\n%s\n", 
			meta.name, 
			meta.artist,
			meta.rigger,
			meta.copyright
		);

		foreach(ref Texture tex; puppets[i-1].textureCache.cache) {
			tex.id = cast(void*)nogc_new!GLTexture(GL_RGBA, tex.width, tex.height, tex.pixels.ptr);
		}
	}

	//
	//			MASK BUFFER
	//
	GLFramebuffer maskFB = nogc_new!GLFramebuffer(sceneWidth, sceneHeight, "Mask FB");
	maskFB.attach(nogc_new!GLTexture(GL_RED, sceneWidth, sceneHeight));

	GLShader maskShader  = nogc_new!GLShader(import("mask.vert"), import("mask.frag"), "mask program");
	GLint maskModelViewMatrix = maskShader.getUniformLocation("modelViewMatrix");
	GLint maskMode = maskShader.getUniformLocation("maskMode");
							
	//
	//			MAIN BUFFER
	//
	GLFramebuffer mainFB = nogc_new!GLFramebuffer(sceneWidth, sceneHeight, "Main FB");
	foreach(i; 0..4)
		mainFB.attach(nogc_new!GLTexture(GL_RGBA, sceneWidth, sceneHeight));

	GLShader mainShader = nogc_new!GLShader(import("basic.vert"), import("basic.frag"), "main program");
	GLint mainModelViewMatrix = mainShader.getUniformLocation("modelViewMatrix");
	GLint mainOpacity = mainShader.getUniformLocation("opacity");

	//
	//			COMPOSITE BUFFERS
	//
	GLFramebuffer[] compFBs;
	GLFramebuffer activeFB;

	//
	//			BUFFER STATE
	//
	GLuint vao;
	GLuint[2] buffers;

	glGenVertexArrays(1, &vao);
	glBindVertexArray(vao);

	glGenBuffers(2, buffers.ptr);
	glBindBuffer(GL_ARRAY_BUFFER, buffers[0]);

	glEnableVertexAttribArray(0);
	glVertexAttribPointer(0, 2, GL_FLOAT, false, VtxData.sizeof, null);
	glEnableVertexAttribArray(1);
	glVertexAttribPointer(1, 2, GL_FLOAT, false, VtxData.sizeof, cast(void*)8);

	glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, buffers[1]);


	Camera2D cam = new Camera2D();
	cam.scale = 0.25;

	double lastTime = 0;
	size_t dIdx = 0;
	float x = 0;

	glDisable(GL_CULL_FACE);
	glDisable(GL_DEPTH_TEST);
	glDisable(GL_STENCIL_TEST);
	glEnable(GL_BLEND);

	while(!glfwWindowShouldClose(window)) {
		double currTime = glfwGetTime();
		double deltaTime = currTime-lastTime;

		// Setup GL frame state.
		glClear(GL_COLOR_BUFFER_BIT);
		glfwGetFramebufferSize(window, &sceneWidth, &sceneHeight);
		glViewport(0, 0, sceneWidth, sceneHeight);

		// Update Camera
		cam.size = vec2(sceneWidth, sceneHeight);
		cam.update();

		x = sin(currTime*2) * 512;

		mainFB.resize(sceneWidth, sceneHeight);
		maskFB.resize(sceneWidth, sceneHeight);
		foreach(comp; compFBs)
			comp.resize(sceneWidth, sceneHeight);
		
		activeFB = mainFB;
		foreach(puppet; puppets) {
			// foreach(param; puppet.parameters)
			// 	param.normalizedValue = vec2((sin(currTime)+1.0)/2.0, (cos(currTime)+1.0)/2.0);

			puppet.update(cast(float)deltaTime);
			puppet.draw(cast(float)deltaTime);
		
			glBufferData(GL_ARRAY_BUFFER, puppet.drawList.vertices.length*VtxData.sizeof, puppet.drawList.vertices.ptr, GL_DYNAMIC_DRAW);
			glBufferData(GL_ELEMENT_ARRAY_BUFFER, puppet.drawList.indices.length*uint.sizeof, puppet.drawList.indices.ptr, GL_DYNAMIC_DRAW);

			// Clear Mask
			maskFB.use();
			maskShader.use();
			glClearColor(1, 1, 1, 1);
			glClear(GL_COLOR_BUFFER_BIT);

			activeFB.use();
			mainShader.use();
			glClearColor(0, 0, 0, 0);
			glClear(GL_COLOR_BUFFER_BIT);

			uint maskStep = 0;
			uint compositeDepth = 0;
			cmds: foreach(DrawCmd cmd; puppet.drawList.commands) {
				final switch(cmd.state) {
					case DrawState.normal:
						if (maskStep > 0) {
							maskStep = 0;

							// Disable masking.
							maskFB.use();
							glClearColor(1, 1, 1, 1);
							glClear(GL_COLOR_BUFFER_BIT);
							glClearColor(0, 0, 0, 0);

							// Re-enable main FB.
							activeFB.use();
							mainShader.use();
						}

						mainShader.setUniform(mainModelViewMatrix, cam.matrix);
						mainShader.setUniform(mainOpacity, cmd.opacity);
						maskFB.textures[0].bind(0);
						foreach(i, src; cmd.sources) {
							if (src !is null)
								(cast(GLTexture)src.id).bind(cast(uint)i+1);
						}

						inSetBlendModeLegacy(cmd.blendMode);
						glDrawElementsBaseVertex(
							GL_TRIANGLES, 
							cmd.elemCount, 
							GL_UNSIGNED_INT, 
							cast(void*)(cmd.idxOffset*4), 
							cmd.vtxOffset
						);
						break;
					
					case DrawState.defineMask:
						if (maskStep != 1) {
							maskStep = 1;
							
							// Start mask FB
							maskFB.use();
							maskShader.use();

							// Clear mask buffer and set blend mode.
							glClearColor(0, 0, 0, 0);
							glClear(GL_COLOR_BUFFER_BIT);
							glBlendFunc(GL_ONE, GL_ONE);
						}

						maskShader.setUniform(maskModelViewMatrix, cam.matrix);
						maskShader.setUniform(maskMode, cmd.maskMode == MaskingMode.mask);
						(cast(GLTexture)cmd.sources[0].id).bind(0);

						glDrawElementsBaseVertex(
							GL_TRIANGLES, 
							cmd.elemCount, 
							GL_UNSIGNED_INT, 
							cast(void*)(cmd.idxOffset*4), 
							cmd.vtxOffset
						);
						break;
					
					case DrawState.maskedDraw:
						if (maskStep == 0)
							continue cmds;

						// Start main FB
						if (maskStep == 1) {
							maskStep = 2;
							activeFB.use();
							mainShader.use();
						}

						mainShader.setUniform(mainModelViewMatrix, cam.matrix);
						mainShader.setUniform(mainOpacity, cmd.opacity);
						maskFB.textures[0].bind(0);
						foreach(i, src; cmd.sources) {
							if (src !is null)
								(cast(GLTexture)src.id).bind(cast(uint)i+1);
						}

						inSetBlendModeLegacy(cmd.blendMode);
						glDrawElementsBaseVertex(
							GL_TRIANGLES, 
							cmd.elemCount, 
							GL_UNSIGNED_INT, 
							cast(void*)(cmd.idxOffset*4), 
							cmd.vtxOffset
						);
						break;
					
					case DrawState.compositeBegin:
						compositeDepth++;
						if (compositeDepth >= compFBs.length) {
							import std.conv : text;
							compFBs ~= nogc_new!GLFramebuffer(sceneWidth, sceneHeight, "Composite "~compositeDepth.text);
							foreach(i; 0..4)
								compFBs[$-1].attach(nogc_new!GLTexture(GL_RGBA, sceneWidth, sceneHeight));
						}

						activeFB = compFBs[compositeDepth-1];
						activeFB.use();
						glClear(GL_COLOR_BUFFER_BIT);
						break;

					case DrawState.compositeEnd:
						compositeDepth--;
						activeFB = compositeDepth > 0 ? compFBs[compositeDepth-1] : mainFB;
						activeFB.use();
						break;

					case DrawState.compositeBlit:
						maskFB.textures[0].bind(0);
						compFBs[compositeDepth].bindAsTarget(1);

						mainShader.use();
						mainShader.setUniform(mainModelViewMatrix, mat4.identity);
						mainShader.setUniform(mainOpacity, cmd.opacity);
						inSetBlendModeLegacy(cmd.blendMode);
						glDrawElementsBaseVertex(
							GL_TRIANGLES, 
							cmd.elemCount, 
							GL_UNSIGNED_INT, 
							cast(void*)(cmd.idxOffset*4), 
							cmd.vtxOffset
						);
						break;
				}
			}
		}

		glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
		mainFB.blitTo(null);
		
		// End of loop stuff
		glfwSwapBuffers(window);
		glfwPollEvents();

		lastTime = currTime;
		dIdx++;
	}
}