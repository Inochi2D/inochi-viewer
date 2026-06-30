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
import inochi2d.core.math;
import numath;
import gl;

alias CompositeStack 	= GLFramebufferStack!("Composite", IN_MAX_ATTACHMENTS);
alias MaskStack 		= GLFramebufferStack!("Mask", 1, GL_RED);

void printNode(Node n, int depth = 0) {
	foreach(i; 0..depth) {
		write(i+1 == depth ? "- " : "  ");
	}

	writefln("%s %s %s %s", n.name, n.matrix.translation.data, n.matrix.scale.data, n.zSort);
	foreach(c; n.children)
		printNode(c, depth+1);
}

GLFWwindow* window;
void main(string[] args)
{
	if (args.length == 1) {
		writeln("No model specified!");
		return;
	}

	IOSink sink;
	sink.info = (const(char)* msg, const(char)* file, uint line) @nogc nothrow {
		printf("%s(%d): %s\n", file, line, msg);
	};
	sink.warning = (const(char)* msg, const(char)* file, uint line) @nogc nothrow {
		printf("warn %s(%d): %s\n", file, line, msg);
	};
	sink.error = (const(char)* msg, const(char)* file, uint line) @nogc nothrow {
		printf("error %s(%d): %s\n", file, line, msg);
	};

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
		auto puppet = Puppet.fromFile(args[i], sink).getOr(null);
		puppet.root.localTransform.translation.x = (((i)*2048)-halfway)-1024;
		writefln("---Model Info---\n%s by %s\n", 
			puppet.properties.name, 
			puppet.properties.author
		);

		foreach(ref Texture tex; puppet.textureCache.cache) {
			tex.id = cast(void*)nogc_new!GLTexture(GL_RGBA, tex.width, tex.height, tex.pixels.ptr);
		}

		puppets ~= puppet;
	}

	//
	//			MAIN BUFFER
	//
	GLShader mainShader = nogc_new!GLShader(import("basic.vert"), import("basic.frag"), "main program");
	GLint mainModelViewMatrix = mainShader.getUniformLocation("modelViewMatrix");

	//
	//			COMPOSITE BUFFERS
	//
	CompositeStack cfbs = CompositeStack(sceneWidth, sceneHeight);
	GLShader blitShader = nogc_new!GLShader(import("blit.vert"), import("blit.frag"), "blit program");

	//
	//			MASK BUFFER
	//
	MaskStack cmasks = MaskStack(sceneWidth, sceneHeight);
	GLShader maskShader  = nogc_new!GLShader(import("mask.vert"), import("mask.frag"), "mask program");
	GLint maskModelViewMatrix = maskShader.getUniformLocation("modelViewMatrix");
	GLint maskMode = maskShader.getUniformLocation("maskMode");


	//
	//			BUFFER STATE
	//
	GLuint vao;
	GLuint[2] buffers;
	GLuint ubo;

	glGenVertexArrays(1, &vao);
	glBindVertexArray(vao);

	glGenBuffers(2, buffers.ptr);
	glBindBuffer(GL_ARRAY_BUFFER, buffers[0]);
	glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, buffers[1]);

	glEnableVertexAttribArray(0);
	glVertexAttribPointer(0, 2, GL_FLOAT, false, VtxData.sizeof, null);
	glEnableVertexAttribArray(1);
	glVertexAttribPointer(1, 2, GL_FLOAT, false, VtxData.sizeof, cast(void*)8);

	glGenBuffers(1, &ubo);
	glBindBuffer(GL_UNIFORM_BUFFER, ubo);
	glBufferData(GL_UNIFORM_BUFFER, 64, null, GL_DYNAMIC_DRAW);
	glBindBuffer(GL_UNIFORM_BUFFER, 0);

	Camera2D cam = new Camera2D();
	cam.scale = 0.50;

	double lastTime = 0;
	size_t dIdx = 0;
	float x = 0;

	glDisable(GL_CULL_FACE);
	glDisable(GL_DEPTH_TEST);
	glDisable(GL_STENCIL_TEST);
	glEnable(GL_BLEND);


	foreach(puppet; puppets) {
		puppet.update(0.016);
		puppet.draw(0.016);
		printNode(puppet.root);
	}

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

		// Resize textures.
		foreach(comp; cfbs.all)
			comp.resize(sceneWidth, sceneHeight);
		foreach(mask; cmasks.all)
			mask.resize(sceneWidth, sceneHeight);
		
		foreach(puppet; puppets) {
			cmasks.reset();
			cfbs.reset();


			//foreach(param; puppet.parameters)
			//	param.normalizedValue = vec2((sin(currTime)+1.0)/2.0, (cos(currTime)+1.0)/2.0);

			puppet.update(cast(float)deltaTime);
			puppet.draw(cast(float)deltaTime);
		
			glBufferData(GL_ARRAY_BUFFER, puppet.drawList.vertices.length*VtxData.sizeof, puppet.drawList.vertices.ptr, GL_DYNAMIC_DRAW);
			glBufferData(GL_ELEMENT_ARRAY_BUFFER, puppet.drawList.indices.length*uint.sizeof, puppet.drawList.indices.ptr, GL_DYNAMIC_DRAW);

			// Clear Mask
			cmasks.current().use();
			maskShader.use();
			glClearColor(1, 1, 1, 1);
			glClear(GL_COLOR_BUFFER_BIT);

			cfbs.current.use();
			mainShader.use();
			glClearColor(0, 0, 0, 0);
			glClear(GL_COLOR_BUFFER_BIT);

			foreach(DrawCmd cmd; puppet.drawList.commands) {
				glBindBuffer(GL_UNIFORM_BUFFER, ubo);
				glBufferSubData(GL_UNIFORM_BUFFER, 0, 64, cmd.variables.ptr);
				glBindBuffer(GL_UNIFORM_BUFFER, 0);

				glBindBufferRange(GL_UNIFORM_BUFFER, 8, ubo, 0, 64);

				switch(cmd.state) {
					default: break;

					case DrawState.normal:
						cfbs.current.use();
						mainShader.use();

						cmasks.current.textures[0].bind(0);
						foreach(i, src; cmd.sources) {
							if (src !is null)
								(cast(GLTexture)src.id).bind(cast(uint)i+1);
						}

						inSetBlendModeLegacy(cmd.blendMode);
						mainShader.setUniform(mainModelViewMatrix, cam.matrix);
						glDrawElementsBaseVertex(
							GL_TRIANGLES, 
							cmd.elemCount, 
							GL_UNSIGNED_INT, 
							cast(void*)(cmd.idxOffset*4), 
							cmd.vtxOffset
						);
						break;
					
					case DrawState.defineMask:
						cmasks.current.use();
						maskShader.use();
						maskShader.setUniform(maskModelViewMatrix, cam.matrix);
						maskShader.setUniform(maskMode, cast(int)cmd.maskMode);
						(cast(GLTexture)cmd.sources[0].id).bind(0);

						glDrawElementsBaseVertex(
							GL_TRIANGLES, 
							cmd.elemCount, 
							GL_UNSIGNED_INT, 
							cast(void*)(cmd.idxOffset*4), 
							cmd.vtxOffset
						);
						break;
					
					case DrawState.pushMask:
						cmasks.push(sceneWidth, sceneHeight).use();
						maskShader.use();
						
						if (cmasks.depth == 1) {
							final switch(cmd.maskMode) {
								case MaskingMode.mask:
									glClearColor(0, 0, 0, 0);
									glBlendFunc(GL_ONE, GL_ONE);
									break;
								case MaskingMode.dodge:
									glClearColor(1, 1, 1, 1);
									glBlendFunc(GL_ONE, GL_ZERO);
									break;
							}

							glClear(GL_COLOR_BUFFER_BIT);
						} else {

							// Blit last mask to the current mask.
							cmasks.last.blitTo(cmasks.current);
						}
						break;

					case DrawState.popMask:
						glClearColor(0, 0, 0, 0);
						cmasks.pop();
						break;
					
					case DrawState.compositeBegin:
						cfbs.push(sceneWidth, sceneHeight).use();
						glClear(GL_COLOR_BUFFER_BIT);
						break;

					case DrawState.compositeEnd:
						cfbs.pop().use();
						break;

					case DrawState.compositeBlit:
						if (auto blitSrc = cfbs.next) {
							cmasks.current.textures[0].bind(0);
							blitSrc.bindAsTarget(1);

							cfbs.current.use();
							blitShader.use();
							inSetBlendModeLegacy(cmd.blendMode);
							glDrawElementsBaseVertex(
								GL_TRIANGLES, 
								cmd.elemCount, 
								GL_UNSIGNED_INT, 
								cast(void*)(cmd.idxOffset*4), 
								cmd.vtxOffset
							);
						}
						break;
				}
			}
		}

		glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
		cfbs.all[0].blitTo(null);
		
		// End of loop stuff
		glfwSwapBuffers(window);
		glfwPollEvents();

		lastTime = currTime;
		dIdx++;
	}
}