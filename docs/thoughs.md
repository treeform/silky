# Silky UI notes

Silky uses a Fidget-style nested DSL. Hierarchy shows up in indentation, and layout lives next to the widgets it affects.

Dear ImGui
```cpp
ImGui::Text("Hello, world %d", 123);
if (ImGui::Button("Save"))
    MySaveFunction();
ImGui::InputText("string", buf, IM_ARRAYSIZE(buf));
ImGui::SliderFloat("float", &f, 0.0f, 1.0f);
```

Silky
```nim
ui:
  text "hello":
    characters &"Hello, world {123}"
  button "Save":
    MySaveFunction()
  textInput "string", buf
  scrubber "float", f, 0.0, 1.0
```

Dear ImGui Menu Bar
```cpp
// Create a window called "My First Tool", with a menu bar.
ImGui::Begin("My First Tool", &my_tool_active, ImGuiWindowFlags_MenuBar);
if (ImGui::BeginMenuBar())
{
    if (ImGui::BeginMenu("File"))
    {
        if (ImGui::MenuItem("Open..", "Ctrl+O")) { /* Do stuff */ }
        if (ImGui::MenuItem("Save", "Ctrl+S"))   { /* Do stuff */ }
        if (ImGui::MenuItem("Close", "Ctrl+W"))  { my_tool_active = false; }
        ImGui::EndMenu();
    }
    ImGui::EndMenuBar();
}

// Edit a color stored as 4 floats
ImGui::ColorEdit4("Color", my_color);

// Generate samples and plot them
float samples[100];
for (int n = 0; n < 100; n++)
    samples[n] = sinf(n * 0.2f + ImGui::GetTime() * 1.5f);
ImGui::PlotLines("Samples", samples, 100);

// Display contents in a scrolling region
ImGui::TextColored(ImVec4(1,1,0,1), "Important Stuff");
ImGui::BeginChild("Scrolling");
for (int n = 0; n < 50; n++)
    ImGui::Text("%04d: Some text", n);
ImGui::EndChild();
ImGui::End();
```

Silky Menu Bar

```nim
ui:
  subWindow("My First Tool", myToolActive, vec2(100, 100), vec2(400, 500)):
    menuBar:
      menu "File":
        menuItem "Open..", "Ctrl+O":
          openFile()
        menuItem "Save", "Ctrl+S":
          saveFile()
        menuItem "Close", "Ctrl+W":
          myToolActive = false

    # Color and plot widgets are still evolving.
    # Prefer nested text / frame for scrolling content:

    text "important":
      characters "Important Stuff"
      tint rgbx(255, 255, 0, 255)

    frame "scrolling":
      box 360, 200
      for n in 0 ..< 50:
        text "row" & $n:
          characters &"{n:04d}: Some text"
```

See [porting.md](porting.md) for moving older cursor-style Silky code to this DSL.
