# Registra ios/Runner/PrivacyInfo.xcprivacy en el proyecto Xcode generado por
# Flutter: lo añade al grupo Runner y a la fase de recursos del target Runner.
# Es idempotente. Se ejecuta en CI (macOS) después de apply_ios_overlay.py.
require 'xcodeproj'

project_path = 'ios/Runner.xcodeproj'
manifest = 'PrivacyInfo.xcprivacy'

unless File.exist?(File.join('ios', 'Runner', manifest))
  abort "Falta ios/Runner/#{manifest}: ejecuta apply_ios_overlay.py antes."
end

project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'Runner' }
abort 'No se encontró el target Runner' unless target

group = project.main_group['Runner']
abort 'No se encontró el grupo Runner' unless group

reference = group.files.find { |f| f.path == manifest } || group.new_file(manifest)
phase = target.resources_build_phase
phase.add_file_reference(reference) unless phase.files_references.include?(reference)

project.save
puts "Privacy manifest registrado en el target Runner"
