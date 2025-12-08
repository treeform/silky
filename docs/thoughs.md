
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
text "Hello, world {123}"
button("Save"):
  MySaveFunction()
inputText("string", buf)
liderFloat("float", f, 0.0, 1.0)
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
begin("My First Tool", myToolActive, MenuBarFlags):
  beginMenuBar():
    menu("File"):
      menuItem("Open..", "Ctrl+O"):
        MySaveFunction()
      menuItem("Save", "Ctrl+S"):
        MySaveFunction()
      menuItem("Close", "Ctrl+W"):
        myToolActive = false

  colorEdit("Color", myColor)

  var samples: seq[float32]
  for n in 0 ..< 100:
    samples.add(sin(n * 0.2 + getTime() * 1.5))
  plotLines("Samples", samples, 100)

  text("Important Stuff", rgbx(1, 1, 0, 1))
  beginChild("Scrolling"):
    for n in 0 ..< 50:
      text(&"{n:04d}: Some text")
```


